/* -*-C-*-

$Id: xdebug.c,v 9.34 2000/12/05 21:23:49 cph Exp $

Copyright (c) 1987-2000 Massachusetts Institute of Technology

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

/* This file contains primitives to debug memory management. */

#include "scheme.h"
#include "prims.h"

/* New debugging utilities */

#define FULL_EQ		0
#define ADDRESS_EQ	2
#define DATUM_EQ	3

static SCHEME_OBJECT *
DEFUN (Find_Occurrence, (From, To, What, Mode),
       fast SCHEME_OBJECT * From
       AND fast SCHEME_OBJECT * To
       AND SCHEME_OBJECT What
       AND int Mode)
{
  fast SCHEME_OBJECT Obj;

  switch (Mode)
  { default:
    case FULL_EQ:
    {
      Obj = What;
      for (; From < To; From++)
      {
	if (OBJECT_TYPE (*From) == TC_MANIFEST_NM_VECTOR)
	{
	  From += OBJECT_DATUM (*From);
	}
	else if (*From == Obj)
	{
	  return From;
	}
      }
     return To;
    }

    case ADDRESS_EQ:
    {
      Obj = OBJECT_DATUM (What);
      for (; From < To; From++)
      {
	if (OBJECT_TYPE (*From) == TC_MANIFEST_NM_VECTOR)
	{
	  From += OBJECT_DATUM (*From);
	}
	else if ((OBJECT_DATUM (*From) == Obj) &&
		 (!(GC_Type_Non_Pointer(*From))))
	{
	  return From;
	}
      }
      return To;
    }
    case DATUM_EQ:
    {
      Obj = OBJECT_DATUM (What);
      for (; From < To; From++)
      {
	if (OBJECT_TYPE (*From) == TC_MANIFEST_NM_VECTOR)
	{
	  From += OBJECT_DATUM (*From);
	}
	else if (OBJECT_DATUM (*From) == Obj)
	{
	  return From;
	}
      }
      return To;
    }
  }
}

#define PRINT_P		1
#define STORE_P		2

static long
DEFUN (Find_In_Area, (Name, From, To, Obj, Mode, print_p, store_p),
       char * Name
       AND SCHEME_OBJECT * From AND SCHEME_OBJECT * To AND SCHEME_OBJECT Obj
       AND int Mode
       AND Boolean print_p AND Boolean store_p)
{
  fast SCHEME_OBJECT *Where;
  fast long occurrences = 0;

  if (print_p)
  {
    outf_console("    Looking in %s:\n", Name);
  }
  Where = From-1;

  while ((Where = Find_Occurrence(Where+1, To, Obj, Mode)) < To)
  {
    occurrences += 1;
    if (print_p)
#if (SIZEOF_UNSIGNED_LONG == 4)
      outf_console("Location = 0x%08lx; Contents = 0x%08lx\n",
	     ((long) Where), ((long) (*Where)));
#else
      outf_console("Location = 0x%lx; Contents = 0x%lx\n",
	     ((long) Where), ((long) (*Where)));
#endif
    if (store_p)
      *Free++ = (LONG_TO_UNSIGNED_FIXNUM ((long) Where));
  }
  return occurrences;
}

SCHEME_OBJECT
DEFUN (Find_Who_Points, (Obj, Find_Mode, Collect_Mode),
       SCHEME_OBJECT Obj
       AND int Find_Mode AND int Collect_Mode)
{
  long n = 0;
  SCHEME_OBJECT *Saved_Free = Free;
  Boolean print_p = (Collect_Mode & PRINT_P);
  Boolean store_p = (Collect_Mode & STORE_P);

  /* No overflow check done. Hopefully referenced few times, or invoked before
     to find the count and insure that there is enough space. */
  if (store_p)
  {
    Free += 1;
  }
  if (print_p)
  {
    putchar('\n');
#if (SIZEOF_UNSIGNED_LONG == 4)
    outf_console("*** Looking for Obj = 0x%08lx; Find_Mode = %2ld ***\n",
	   ((long) Obj), ((long) Find_Mode));
#else
    outf_console("*** Looking for Obj = 0x%lx; Find_Mode = %2ld ***\n",
	   ((long) Obj), ((long) Find_Mode));
#endif
  }
  n += Find_In_Area("Constant Space",
		    Constant_Space, Free_Constant, Obj,
		    Find_Mode, print_p, store_p);
  n += Find_In_Area("the Heap",
		    Heap_Bottom, Saved_Free, Obj,
		    Find_Mode, print_p, store_p);
#ifndef USE_STACKLETS
  n += Find_In_Area("the Stack",
		    Stack_Pointer, Stack_Top, Obj,
		    Find_Mode, print_p, store_p);
#endif
  if (print_p)
  {
    outf_console("Done.\n");
  }
  if (store_p)
  {
    *Saved_Free = (MAKE_OBJECT (TC_MANIFEST_VECTOR, n));
    return (MAKE_POINTER_OBJECT (TC_VECTOR, Saved_Free));
  }
  else
  {
    return (LONG_TO_FIXNUM (n));
  }
}

void
DEFUN (Print_Memory, (Where, How_Many),
       SCHEME_OBJECT * Where
       AND long How_Many)
{
  fast SCHEME_OBJECT *End   = &Where[How_Many];

#if (SIZEOF_UNSIGNED_LONG == 4)
  outf_console ("\n*** Memory from 0x%08lx to 0x%08lx (excluded) ***\n",
	  ((long) Where), ((long) End));
  while (Where < End)
  {
    outf_console ("0x%0l8x\n", ((long) (*Where++)));
  }
#else
  outf_console ("\n*** Memory from 0x%lx to 0x%lx (excluded) ***\n",
	  ((long) Where), ((long) End));
  while (Where < End)
  {
    outf_console ("0x%lx\n", ((long) (*Where++)));
  }
#endif
  outf_console ("Done.\n");
  return;
}

/* Primitives to give scheme a handle on utilities from DEBUG.C */

DEFINE_PRIMITIVE ("DEBUG-SHOW-PURE", Prim_debug_show_pure, 0, 0, 0)
{
  PRIMITIVE_HEADER (0);

  outf_console ("\n*** Constant & Pure Space: ***\n");
  Show_Pure ();
  PRIMITIVE_RETURN (UNSPECIFIC);
}

DEFINE_PRIMITIVE ("DEBUG-SHOW-ENV", Prim_debug_show_env, 1, 1, 0)
{
  SCHEME_OBJECT environment;
  PRIMITIVE_HEADER (1);

  environment = (ARG_REF (1));
  outf_console ("\n*** Environment = 0x%lx ***\n", ((long) environment));
  Show_Env (environment);
  PRIMITIVE_RETURN (UNSPECIFIC);
}

DEFINE_PRIMITIVE ("DEBUG-STACK-TRACE", Prim_debug_stack_trace, 0, 0, 0)
{
  PRIMITIVE_HEADER (0);

  outf_console ("\n*** Back Trace: ***\n");
  Back_Trace (console_output);
  PRIMITIVE_RETURN (UNSPECIFIC);
}

DEFINE_PRIMITIVE ("DEBUG-FIND-SYMBOL", Prim_debug_find_symbol, 1, 1, 0)
{
  extern SCHEME_OBJECT EXFUN (find_symbol, (long, unsigned char *));
  PRIMITIVE_HEADER (1);

  CHECK_ARG (1, STRING_P);
  {
    fast SCHEME_OBJECT string = (ARG_REF (1));
    fast SCHEME_OBJECT symbol = (find_symbol ((STRING_LENGTH (string)),
					      (STRING_LOC (string, 0))));
    if (symbol == SHARP_F)
      outf_console ("\nNot interned.\n");
    else
      {
	outf_console ("\nInterned Symbol: 0x%lx", ((long) symbol));
	Print_Expression (MEMORY_REF (symbol, SYMBOL_GLOBAL_VALUE), "Value");
	outf_console ("\n");
      }
  }
  PRIMITIVE_RETURN (UNSPECIFIC);
}

/* Primitives to give scheme a handle on utilities in this file. */

DEFINE_PRIMITIVE ("DEBUG-EDIT-FLAGS", Prim_debug_edit_flags, 0, 0, 0)
{
  PRIMITIVE_HEADER (0);
  debug_edit_flags ();
  PRIMITIVE_RETURN (UNSPECIFIC);
}

DEFINE_PRIMITIVE ("DEBUG-FIND-WHO-POINTS", Prim_debug_find_who_points, 3, 3, 0)
{
  PRIMITIVE_HEADER (3);
  PRIMITIVE_RETURN
    (Find_Who_Points
     ((ARG_REF (1)),
      (OBJECT_DATUM (ARG_REF (2))),
      (OBJECT_DATUM (ARG_REF (3)))));
}

DEFINE_PRIMITIVE ("DEBUG-PRINT-MEMORY", Prim_debug_print_memory, 2, 2, 0)
{
  SCHEME_OBJECT object;
  PRIMITIVE_HEADER (2);
  object = (ARG_REF (1));
  Print_Memory
    (((GC_Type_Non_Pointer (object))
      ? ((SCHEME_OBJECT *) (OBJECT_DATUM (object)))
      : (OBJECT_ADDRESS (object))),
     (OBJECT_DATUM (ARG_REF (2))));
  PRIMITIVE_RETURN (UNSPECIFIC);
}