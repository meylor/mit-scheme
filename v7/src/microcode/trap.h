/* -*-C-*-

$Id: trap.h,v 9.48 2001/08/07 01:27:13 cph Exp $

Copyright (c) 1987-1989, 1999-2001 Massachusetts Institute of Technology

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
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307,
USA.
*/

#ifndef SCM_TRAP_H
#define SCM_TRAP_H

/* Kinds of traps:

   For efficiency, some traps are immediate, while some are
   pointer objects.  The type code is multiplexed, and the
   garbage collector handles it specially.

   The odd-numbered traps used to be "dangerous" versions of the
   even-numbered ones, but all that complexity has been flushed.  */

typedef unsigned long trap_kind_t;

/* The following are immediate traps: */
#define TRAP_UNASSIGNED				0
#define TRAP_UNBOUND				2
#define TRAP_EXPENSIVE				6
/* TRAP_MAX_IMMEDIATE is defined in const.h */

/* The following are non-immediate traps: */
#define TRAP_COMPILER_CACHED			14

/* Usages of the above traps:
   TRAP_UNASSIGNED can appear in a value cell or a cache.
   TRAP_UNBOUND can appear in the following locations:
     * The value cell of a global variable.  All symbols initially
       have their value cell set to UNBOUND_OBJECT.
     * A cache that is in the value cell of a global variable.  This
       is like the previous case except that some compiled code has
       referenced the unbound variable.
     * The value cell of a procedure's argument frame.  This is caused
       by calling unbind_variable on a procedure's argument.
     * A cache that is not stored in an environment.  This is caused
       by referring to an unbound variable in an environment that does
       not inherit from the global environment.
   TRAP_EXPENSIVE can only appear in a "clone" cache.  This causes
     assignments to this cache to trap out to the microcode, where the
     updating of the variable's associated UUO links can be performed.
   TRAP_COMPILER_CACHED can only appear in a value cell.  It is used
     to associate a cache with the variable.  */

/* The following never appear in value cells.  */
/* NON_TRAP_KIND is returned by get_trap_kind when its argument is not
   a reference trap object.  */
#define NON_TRAP_KIND				32

/* The garbage collector knows that pointers of type CACHE_TYPE point
   to three words of storage, because these pointers are embedded in
   compiled-code linkage sections (TC_LINKAGE_SECTION) without types.
   */
#define CACHE_TYPE				TC_HUNK3
#define CACHE_REFERENCES_TYPE			TC_HUNK3

#if (SIZEOF_UNSIGNED_LONG == 4)	/* 32 bit objects */
#  if (TYPE_CODE_LENGTH == 8)
#    define UNASSIGNED_OBJECT	0x32000000
#    define UNBOUND_OBJECT	0x32000002
#    define EXPENSIVE_OBJECT	0x32000006
#  endif
#  if (TYPE_CODE_LENGTH == 6)
#    define UNASSIGNED_OBJECT	0xc8000000
#    define UNBOUND_OBJECT	0xc8000002
#    define EXPENSIVE_OBJECT	0xc8000006
#  endif
#  if (TC_REFERENCE_TRAP != 0x32)
#    include "error: trap.h and types.h are inconsistent"
#  endif
#endif

#ifndef UNASSIGNED_OBJECT	/* Safe version */
#  define UNASSIGNED_OBJECT (MAKE_OBJECT (TC_REFERENCE_TRAP, TRAP_UNASSIGNED))
#  define UNBOUND_OBJECT    (MAKE_OBJECT (TC_REFERENCE_TRAP, TRAP_UNBOUND))
#  define EXPENSIVE_OBJECT  (MAKE_OBJECT (TC_REFERENCE_TRAP, TRAP_EXPENSIVE))
#endif

#endif /* not SCM_TRAP_H */