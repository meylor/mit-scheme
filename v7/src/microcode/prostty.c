/* -*-C-*-

$Id: prostty.c,v 1.7 1999/01/02 06:11:34 cph Exp $

Copyright (c) 1987-1999 Massachusetts Institute of Technology

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

/* Primitives to perform I/O to and from the console. */

#include "scheme.h"
#include "prims.h"
#include "ostty.h"
#include "osctty.h"
#include "osfile.h"
#include "osio.h"

DEFINE_PRIMITIVE ("TTY-INPUT-CHANNEL", Prim_tty_input_channel, 0, 0,
  "Return the standard input channel.")
{
  PRIMITIVE_HEADER (0);
  PRIMITIVE_RETURN (long_to_integer (OS_tty_input_channel ()));
}

DEFINE_PRIMITIVE ("TTY-OUTPUT-CHANNEL", Prim_tty_output_channel, 0, 0,
  "Return the standard output channel.")
{
  PRIMITIVE_HEADER (0);
  PRIMITIVE_RETURN (long_to_integer (OS_tty_output_channel ()));
}

DEFINE_PRIMITIVE ("TTY-X-SIZE", Prim_tty_x_size, 0, 0,
  "Return the display width in character columns.")
{
  PRIMITIVE_HEADER (0);
  PRIMITIVE_RETURN (long_to_integer (OS_tty_x_size ()));
}

DEFINE_PRIMITIVE ("TTY-Y-SIZE", Prim_tty_y_size, 0, 0,
  "Return the display height in character lines.")
{
  PRIMITIVE_HEADER (0);
  PRIMITIVE_RETURN (long_to_integer (OS_tty_y_size ()));
}

DEFINE_PRIMITIVE ("TTY-COMMAND-BEEP", Prim_tty_command_beep, 0, 0,
  "Return a string that, when written to the display, will make it beep.")
{
  PRIMITIVE_HEADER (0);
  PRIMITIVE_RETURN
    (char_pointer_to_string ((unsigned char *) (OS_tty_command_beep ())));
}

DEFINE_PRIMITIVE ("TTY-COMMAND-CLEAR", Prim_tty_command_clear, 0, 0,
  "Return a string that, when written to the display, will clear it.")
{
  PRIMITIVE_HEADER (0);
  PRIMITIVE_RETURN
    (char_pointer_to_string ((unsigned char *) (OS_tty_command_clear ())));
}

DEFINE_PRIMITIVE ("TTY-NEXT-INTERRUPT-CHAR", Prim_tty_next_interrupt_char, 0, 0,
  "Return the next interrupt character in the console input buffer.\n\
The character is returned as an unsigned integer.")
{
  PRIMITIVE_HEADER (0);
  PRIMITIVE_RETURN (long_to_integer (OS_tty_next_interrupt_char ()));
}

DEFINE_PRIMITIVE ("TTY-GET-INTERRUPT-ENABLES", Prim_tty_get_interrupt_enables, 0, 0,
  "Return the current keyboard interrupt enables.")
{
  PRIMITIVE_HEADER (0);
  {
    Tinterrupt_enables mask;
    OS_ctty_get_interrupt_enables (&mask);
    PRIMITIVE_RETURN (long_to_integer (mask));
  }
}

DEFINE_PRIMITIVE ("TTY-SET-INTERRUPT-ENABLES", Prim_tty_set_interrupt_enables, 1, 1,
  "Change the keyboard interrupt enables to MASK.")
{
  PRIMITIVE_HEADER (1);
  {
    Tinterrupt_enables mask = (arg_integer (1));
    OS_ctty_set_interrupt_enables (&mask);
  }
  PRIMITIVE_RETURN (UNSPECIFIC);
}

DEFINE_PRIMITIVE ("TTY-GET-INTERRUPT-CHARS", Prim_tty_get_interrupt_chars, 0, 0,
  "Return the current interrupt characters as a string.")
{
  PRIMITIVE_HEADER (0);
  {
    unsigned int i;
    unsigned int num_chars = (OS_ctty_num_int_chars ());
    SCHEME_OBJECT result = (allocate_string (num_chars * 2));
    cc_t * int_chars = (OS_ctty_get_int_chars ());
    cc_t * int_handlers = (OS_ctty_get_int_char_handlers ());
    unsigned char * scan = (STRING_LOC (result, 0));

    for (i = 0; i < num_chars; i++)
    {
      (*scan++) = ((unsigned char) int_chars[i]);
      (*scan++) = ((unsigned char) int_handlers[i]);
    }
    PRIMITIVE_RETURN (result);
  }
}

DEFINE_PRIMITIVE ("TTY-SET-INTERRUPT-CHARS!", Prim_tty_set_interrupt_chars, 1, 1,
  "Change the current interrupt characters to STRING.\n\
STRING must be in the correct form for this operating system.")
{
  PRIMITIVE_HEADER (1);
  {
    unsigned int i;
    unsigned int num_chars = (OS_ctty_num_int_chars ());
    cc_t * int_chars = (OS_ctty_get_int_chars ());
    cc_t * int_handlers = (OS_ctty_get_int_char_handlers ());
    SCHEME_OBJECT argument = (ARG_REF (1));
    unsigned char * scan;

    if (! ((STRING_P (argument))
	   && (((unsigned int) (STRING_LENGTH (argument)))
	       == (num_chars * 2))))
      error_wrong_type_arg (1);

    for (i = 0, scan = (STRING_LOC (argument, 0)); i < num_chars; i++)
    {
      int_chars[i] = (*scan++);
      int_handlers[i] = (*scan++);
    }
    OS_ctty_set_int_chars (int_chars);
    OS_ctty_set_int_char_handlers (int_handlers);
  }
  PRIMITIVE_RETURN (UNSPECIFIC);
}