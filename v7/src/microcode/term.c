/* -*-C-*-

$Id: term.c,v 1.15 2000/12/05 21:23:48 cph Exp $

Copyright (c) 1990-2000 Massachusetts Institute of Technology

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
*/

#include "scheme.h"
#include "ostop.h"
#include "osio.h"
#include "osfs.h"
#include "osfile.h"
#include "edwin.h"

extern long death_blow;
extern char * Term_Messages [];
extern void EXFUN (get_band_parameters, (long * heap_size, long * const_size));
extern void EXFUN (Reset_Memory, (void));

#ifdef __WIN32__
#  define USING_MESSAGE_BOX_FOR_FATAL_OUTPUT
   extern void win32_deallocate_registers (void);
#endif

#ifdef __OS2__
#  define USING_MESSAGE_BOX_FOR_FATAL_OUTPUT
#endif

static void EXFUN (edwin_auto_save, (void));
static void EXFUN (delete_temp_files, (void));

#define BYTES_TO_BLOCKS(n) (((n) + 1023) / 1024)
#define MIN_HEAP_DELTA	50

#ifndef EXIT_SCHEME
#  define EXIT_SCHEME exit
#endif

#ifdef EXIT_SCHEME_DECLARATIONS
EXIT_SCHEME_DECLARATIONS;
#endif

void
DEFUN_VOID (init_exit_scheme)
{
#ifdef INIT_EXIT_SCHEME
  INIT_EXIT_SCHEME ();
#endif
}

static void
DEFUN (attempt_termination_backout, (code), int code)
{
  outf_flush_error(); /* NOT flush_fatal */
  if ((WITHIN_CRITICAL_SECTION_P ())
      || (code == TERM_HALT)
      || (! (Valid_Fixed_Obj_Vector ())))
    return;
  {
    SCHEME_OBJECT Term_Vector = (Get_Fixed_Obj_Slot (Termination_Proc_Vector));
    if ((! (VECTOR_P (Term_Vector)))
	|| (((long) (VECTOR_LENGTH (Term_Vector))) <= code))
      return;
    {
      SCHEME_OBJECT Handler = (VECTOR_REF (Term_Vector, code));
      if (Handler == SHARP_F)
	return;
     Will_Push (CONTINUATION_SIZE
		+ STACK_ENV_EXTRA_SLOTS
		+ ((code == TERM_NO_ERROR_HANDLER) ? 5 : 4));
      Store_Return (RC_HALT);
      Store_Expression (LONG_TO_UNSIGNED_FIXNUM (code));
      Save_Cont ();
      if (code == TERM_NO_ERROR_HANDLER)
	STACK_PUSH (LONG_TO_UNSIGNED_FIXNUM (death_blow));
      STACK_PUSH (Val);			/* Arg 3 */
      STACK_PUSH (Fetch_Env ());	/* Arg 2 */
      STACK_PUSH (Fetch_Expression ()); /* Arg 1 */
      STACK_PUSH (Handler);		/* The handler function */
      STACK_PUSH (STACK_FRAME_HEADER
		  + ((code == TERM_NO_ERROR_HANDLER) ? 4 : 3));
     Pushed ();
      abort_to_interpreter (PRIM_NO_TRAP_APPLY);
    }
  }
}

static void
DEFUN (termination_prefix, (code), int code)
{
  attempt_termination_backout (code);
  OS_restore_external_state ();
  /* TERM_HALT is not an error condition and thus its termination
     message should be considered normal output.  */
  if (code == TERM_HALT)
    {
      outf_console ("\n%s.\n", (Term_Messages [code]));
      outf_flush_console ();
    }
  else
    {
#ifdef USING_MESSAGE_BOX_FOR_FATAL_OUTPUT
      outf_fatal ("Reason for termination:");
#endif
      outf_fatal ("\n");
      if ((code < 0) || (code > MAX_TERMINATION))
	outf_fatal ("Unknown termination code 0x%x", code);
      else
	outf_fatal ("%s", (Term_Messages [code]));
      if (WITHIN_CRITICAL_SECTION_P ())
	outf_fatal (" within critical section \"%s\"",
		    (CRITICAL_SECTION_NAME ()));
      outf_fatal (".");
#ifndef USING_MESSAGE_BOX_FOR_FATAL_OUTPUT
      outf_fatal ("\n");
#endif
    }
}

static void
DEFUN (termination_suffix, (code, value, abnormal_p),
       int code AND int value AND int abnormal_p)
{
#ifdef EXIT_HOOK
  EXIT_HOOK (code, value, abnormal_p);
#endif
  edwin_auto_save ();
  delete_temp_files ();
#ifdef USING_MESSAGE_BOX_FOR_FATAL_OUTPUT
  /* Don't put up message box for ordinary exit.  */
  if (code != TERM_HALT)
#endif
    outf_flush_fatal();
#ifdef __WIN32__
  win32_deallocate_registers();
#endif
  Reset_Memory ();
  EXIT_SCHEME (value);
}

static void
DEFUN (termination_suffix_trace, (code), int code)
{
  if (Trace_On_Error)
    {
      outf_error ("\n\n**** Stack trace ****\n\n");
      Back_Trace (error_output);
    }
  termination_suffix (code, 1, 1);
}

void
DEFUN (Microcode_Termination, (code), int code)
{
  termination_prefix (code);
  termination_suffix_trace (code);
}

void
DEFUN (termination_normal, (value), CONST int value)
{
  termination_prefix (TERM_HALT);
  termination_suffix (TERM_HALT, value, 0);
}

void
DEFUN_VOID (termination_init_error)
{
  termination_prefix (TERM_EXIT);
  termination_suffix (TERM_EXIT, 1, 1);
}

void
DEFUN_VOID (termination_end_of_computation)
{
  termination_prefix (TERM_END_OF_COMPUTATION);
  Print_Expression (Val, "Final result");
  outf_console("\n");
  termination_suffix (TERM_END_OF_COMPUTATION, 0, 0);
}

void
DEFUN_VOID (termination_trap)
{
  /* This claims not to be abnormal so that the user will
     not be asked a second time about dumping core. */
  termination_prefix (TERM_TRAP);
  termination_suffix (TERM_TRAP, 1, 0);
}

void
DEFUN_VOID (termination_no_error_handler)
{
  /* This does not print a back trace because the caller printed one. */
  termination_prefix (TERM_NO_ERROR_HANDLER);
  if (death_blow == ERR_FASL_FILE_TOO_BIG)
    {
      long heap_size;
      long const_size;
      get_band_parameters (&heap_size, &const_size);
      outf_fatal ("Try again with values at least as large as\n");
      outf_fatal ("  -heap %d (%d + %d)\n",
	       (MIN_HEAP_DELTA + (BYTES_TO_BLOCKS (heap_size))),
	       (BYTES_TO_BLOCKS (heap_size)),
	       MIN_HEAP_DELTA);
      outf_fatal ("  -constant %d\n", (BYTES_TO_BLOCKS (const_size)));
    }
  termination_suffix (TERM_NO_ERROR_HANDLER, 1, 1);
}

void
DEFUN_VOID (termination_gc_out_of_space)
{
  termination_prefix (TERM_GC_OUT_OF_SPACE);
  outf_fatal ("You are out of space at the end of a Garbage Collection!\n");
  outf_fatal ("Free = 0x%lx; MemTop = 0x%lx; Heap_Top = 0x%lx\n",
	      Free, MemTop, Heap_Top);
  outf_fatal ("Words required = %ld; Words available = %ld\n",
	      (MemTop - Free), GC_Space_Needed);
  termination_suffix_trace (TERM_GC_OUT_OF_SPACE);
}

void
DEFUN_VOID (termination_eof)
{
  Microcode_Termination (TERM_EOF);
}

void
DEFUN (termination_signal, (signal_name), CONST char * signal_name)
{
  if (signal_name != 0)
    {
      termination_prefix (TERM_SIGNAL);
      outf_fatal ("Killed by %s.\n", signal_name);
    }
  else
    attempt_termination_backout (TERM_SIGNAL);
  termination_suffix_trace (TERM_SIGNAL);
}

static void
DEFUN_VOID (edwin_auto_save)
{
  static SCHEME_OBJECT position;
  static struct interpreter_state_s new_state;

  position =
    ((Valid_Fixed_Obj_Vector ())
     ? (Get_Fixed_Obj_Slot (FIXOBJ_EDWIN_AUTO_SAVE))
     : EMPTY_LIST);
  while (PAIR_P (position))
    {
      SCHEME_OBJECT entry = (PAIR_CAR (position));
      position = (PAIR_CDR (position));
      if ((PAIR_P (entry))
	  && (GROUP_P (PAIR_CAR (entry)))
	  && (STRING_P (PAIR_CDR (entry)))
	  && ((GROUP_MODIFIED_P (PAIR_CAR (entry))) == SHARP_T))
	{
	  SCHEME_OBJECT group = (PAIR_CAR (entry));
	  char * namestring = ((char *) (STRING_LOC ((PAIR_CDR (entry)), 0)));
	  SCHEME_OBJECT text = (GROUP_TEXT (group));
	  unsigned char * start = (STRING_LOC (text, 0));
	  unsigned char * end = (start + (STRING_LENGTH (text)));
	  unsigned char * gap_start = (start + (GROUP_GAP_START (group)));
	  unsigned char * gap_end = (start + (GROUP_GAP_END (group)));
	  if ((start < gap_start) || (gap_end < end))
	    {
	      bind_interpreter_state (&new_state);
	      if ((setjmp (interpreter_catch_env)) == 0)
		{
		  Tchannel channel;
		  outf_error ("Auto-saving file \"%s\"\n", namestring);
		  outf_flush_error ();
		  channel = (OS_open_output_file (namestring));
		  if (start < gap_start)
		    OS_channel_write (channel, start, (gap_start - start));
		  if (gap_end < end)
		    OS_channel_write (channel, gap_end, (end - gap_end));
		  OS_channel_close (channel);
		}
	      unbind_interpreter_state (&new_state);
	    }
	}
    }
}

static void
DEFUN_VOID (delete_temp_files)
{
  static SCHEME_OBJECT position;
  static struct interpreter_state_s new_state;

  position =
    ((Valid_Fixed_Obj_Vector ())
     ? (Get_Fixed_Obj_Slot (FIXOBJ_FILES_TO_DELETE))
     : EMPTY_LIST);
  while (PAIR_P (position))
    {
      SCHEME_OBJECT entry = (PAIR_CAR (position));
      position = (PAIR_CDR (position));
      if (STRING_P (entry))
	{
	  bind_interpreter_state (&new_state);
	  if ((setjmp (interpreter_catch_env)) == 0)
	    OS_file_remove ((char *) (STRING_LOC (entry, 0)));
	  unbind_interpreter_state (&new_state);
	}
    }
}