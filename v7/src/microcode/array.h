/* -*-C-*-

$Id: array.h,v 9.36 1999/01/02 06:11:34 cph Exp $

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

#ifndef REAL_IS_DEFINED_DOUBLE
#define REAL_IS_DEFINED_DOUBLE 0
#endif

#if (REAL_IS_DEFINED_DOUBLE == 0)
#define REAL float
#else
#define REAL double
#endif

#define arg_real(arg_number) ((REAL) (arg_real_number (arg_number)))
#define REAL_SIZE (BYTES_TO_WORDS (sizeof (REAL)))

#define FLOAT_SIZE (BYTES_TO_WORDS (sizeof (float)))
#define DOUBLE_SIZE (BYTES_TO_WORDS (sizeof (double)))

#if (REAL_IS_DEFINED_DOUBLE == 0)

/* Scheme_Arrays are implemented as NON_MARKED_VECTOR. */

#define ARRAY_P NON_MARKED_VECTOR_P
#define ARRAY_LENGTH(array) ((long) (FAST_MEMORY_REF ((array), 1)))
#define ARRAY_CONTENTS(array) ((REAL *) (MEMORY_LOC (array, 2)))

#else /* (REAL_IS_DEFINED_DOUBLE != 0) */

/* Scheme_Arrays are implemented as flonum vectors.
   This is required to get alignment to work right on RISC machines. */

#define ARRAY_P FLONUM_P
#define ARRAY_LENGTH(array) ((VECTOR_LENGTH (array)) / DOUBLE_SIZE)
#define ARRAY_CONTENTS(array) ((REAL *) (MEMORY_LOC (array, 1)))

#endif /* (REAL_IS_DEFINED_DOUBLE != 0) */

extern SCHEME_OBJECT allocate_array ();

extern void C_Array_Find_Min_Max ();
extern void C_Array_Complex_Multiply_Into_First_One ();

extern void C_Array_Make_Histogram ();
/* REAL * Array;
   REAL * Histogram;
   long Length;
   long npoints; */

extern void Find_Offset_Scale_For_Linear_Map();
/* REAL Min;
   REAL Max;
   REAL New_Min;
   REAL New_Max;
   REAL * Offset;
   REAL * Scale; */

/* The following macros implement commonly used array procs. */

/* In the following macros we assign the arguments to local variables
   so as to do any computation (referencing, etc.) only once outside the loop.
   Otherwise it would be done again and again inside the loop.
   The names, like "MCRINDX", have been chosen to avoid shadowing the
   variables that are substituted in.  WARNING: Do not use any names
   starting with the prefix "mcr", when calling these macros */

#define C_Array_Scale(array, scale, n)					\
{									\
  fast REAL * mcr_scan = (array);					\
  fast REAL * mcr_end = (mcr_scan + (n));				\
  fast REAL mcrd0 = (scale);						\
  while (mcr_scan < mcr_end)						\
    (*mcr_scan++) *= mcrd0;						\
}

#define Array_Scale(array, scale)					\
{									\
  C_Array_Scale								\
    ((ARRAY_CONTENTS (array)),						\
     (scale),								\
     (ARRAY_LENGTH (array)));						\
}

#define C_Array_Copy(from, to, n)					\
{									\
  fast REAL * mcr_scan_source = (from);					\
  fast REAL * mcr_end_source = (mcr_scan_source + (n));			\
  fast REAL * mcr_scan_target = (to);					\
  while (mcr_scan_source < mcr_end_source)				\
    (*mcr_scan_target++) = (*mcr_scan_source++);			\
}

#define Array_Copy(from, to)						\
{									\
  C_Array_Copy								\
    ((ARRAY_CONTENTS (from)),						\
     (ARRAY_CONTENTS (to)),						\
     (ARRAY_LENGTH (from)));						\
}

#define C_Array_Add_Into_Second_One(from, to, n)			\
{									\
  fast REAL * mcr_scan_source = (from);					\
  fast REAL * mcr_end_source = (mcr_scan_source + (n));			\
  fast REAL * mcr_scan_target = (to);					\
  while (mcr_scan_source < mcr_end_source)				\
    (*mcr_scan_target++) += (*mcr_scan_source++);			\
}

#define Array_Add_Into_Second_One(from,to)				\
{									\
  C_Array_Add_Into_Second_One						\
    ((ARRAY_CONTENTS (from)),						\
     (ARRAY_CONTENTS (to)),						\
     (ARRAY_LENGTH (from)));						\
}

#define mabs(x) (((x) < 0) ? (- (x)) : (x))
#define max(x,y) (((x) < (y)) ? (y) : (x))
#define min(x,y) (((x) < (y)) ? (x) : (y))