/* Copyright (C) 1990 Free Software Foundation, Inc.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 1, or (at your option)
   any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.  */

/* $Header: /Users/cph/tmp/foo/mit-scheme/mit-scheme/v7/src/microcode/wind.c,v 1.1 1990/06/20 19:38:59 cph Rel $ */

#include <stdio.h>
#include "obstack.h"
#include "dstack.h"
extern void EXFUN (free, (PTR ptr));
#define obstack_chunk_alloc xmalloc
#define obstack_chunk_free free

static void
DEFUN (error, (procedure_name, message),
       CONST char * procedure_name AND
       CONST char * message)
{
  fprintf (stderr, "%s: %s\n", procedure_name, message);
  fflush (stderr);
  abort ();
}

static PTR
DEFUN (xmalloc, (length), unsigned int length)
{
  extern PTR EXFUN (malloc, (unsigned int length));
  PTR result = (malloc (length));
  if (result == 0)
    error ("malloc", "memory allocation failed");
  return (result);
}

struct winding_record
{
  struct winding_record * next;
  void EXFUN ((*protector), (PTR environment));
  PTR environment;
};

static struct obstack dstack;
static struct winding_record * current_winding_record;
PTR dstack_position;

void
DEFUN_VOID (dstack_initialize)
{
  obstack_init (&dstack);
  dstack_position = 0;
  current_winding_record = 0;
}

void
DEFUN_VOID (dstack_reset)
{
  obstack_free ((&dstack), 0);
  dstack_initialize ();
}

#define EXPORT(sp) ((PTR) (((char *) (sp)) + (sizeof (PTR))))

PTR
DEFUN (dstack_alloc, (length), unsigned int length)
{
  PTR chunk = (obstack_alloc ((&dstack), ((sizeof (PTR)) + length)));
  (* ((PTR *) chunk)) = dstack_position;
  dstack_position = chunk;
  return (EXPORT (chunk));
}

void
DEFUN (dstack_protect, (protector, environment),
       void EXFUN ((*protector), (PTR environment)) AND
       PTR environment)
{
  struct winding_record * record =
    (dstack_alloc (sizeof (struct winding_record)));
  (record -> next) = current_winding_record;
  (record -> protector) = protector;
  (record -> environment) = environment;
  current_winding_record = record;
}

void
DEFUN (dstack_set_position, (position), PTR position)
{
  while (dstack_position != position)
    {
      if (dstack_position == 0)
	error ("dstack_set_position", "no more stack");
      if ((EXPORT (dstack_position)) == current_winding_record)
	{
	  PTR sp = dstack_position;
	  struct winding_record * record = current_winding_record;
	  (* (record -> protector)) (record -> environment);
	  if (sp != dstack_position)
	    error ("dstack_set_position", "stack slipped during unwind");
	  current_winding_record = (record -> next);
	}
      {
	PTR * sp = dstack_position;
	dstack_position = (*sp);
	obstack_free ((&dstack), sp);
      }
    }
}

struct binding_record
{
  PTR * location;
  PTR value;
};

static void
DEFUN (undo_binding, (record), PTR record)
{
  (* (((struct binding_record *) record) -> location)) =
    (((struct binding_record *) record) -> value);
}

void
DEFUN (dstack_bind, (location, value), PTR location AND PTR value)
{
  struct binding_record * record =
    (dstack_alloc (sizeof (struct binding_record)));
  (record -> location) = ((PTR *) location);
  (record -> value) = (* ((PTR *) location));
  dstack_protect (undo_binding, record);
  (* ((PTR *) location)) = value;
}
