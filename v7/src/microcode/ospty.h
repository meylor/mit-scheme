/* -*-C-*-

$Id: ospty.h,v 1.4 1999/01/02 06:11:34 cph Exp $

Copyright (c) 1992, 1999 Massachusetts Institute of Technology

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

#ifndef SCM_OSPTY_H
#define SCM_OSPTY_H

#include "os.h"

extern CONST char * EXFUN
  (OS_open_pty_master, (Tchannel * master_fd, CONST char ** master_fname));
extern void EXFUN (OS_pty_master_send_signal, (Tchannel channel, int sig));
extern void EXFUN (OS_pty_master_kill, (Tchannel channel));
extern void EXFUN (OS_pty_master_stop, (Tchannel channel));
extern void EXFUN (OS_pty_master_continue, (Tchannel channel));
extern void EXFUN (OS_pty_master_interrupt, (Tchannel channel));
extern void EXFUN (OS_pty_master_quit, (Tchannel channel));
extern void EXFUN (OS_pty_master_hangup, (Tchannel channel));

#endif /* SCM_OSPTY_H */