/* -*-C-*-

$Id: ntfs.h,v 1.5 2001/05/09 03:14:59 cph Exp $

Copyright (c) 1997-2001 Massachusetts Institute of Technology

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

#include "nt.h"
#include "osfs.h"

enum get_file_info_result { gfi_ok, gfi_not_found, gfi_not_accessible };

extern enum get_file_info_result NT_get_file_info
  (const char *, BY_HANDLE_FILE_INFORMATION *, int);

#define STAT_NOT_FOUND_P(code)						\
  (((code) == ERROR_FILE_NOT_FOUND)					\
   || ((code) == ERROR_PATH_NOT_FOUND)					\
   || ((code) == ERROR_NOT_READY)					\
   || ((code) == ERROR_INVALID_DRIVE)					\
   || ((code) == ERROR_NO_MEDIA_IN_DRIVE))

#define STAT_NOT_ACCESSIBLE_P(code)					\
  (((code) == ERROR_ACCESS_DENIED)					\
   || ((code) == ERROR_SHARING_VIOLATION)				\
   || ((code) == ERROR_DRIVE_LOCKED))