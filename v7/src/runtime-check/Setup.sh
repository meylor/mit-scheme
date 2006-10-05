#!/bin/sh
#
# $Id: Setup.sh,v 1.9 2006/09/25 04:39:12 cph Exp $
#
# Copyright 2000,2001,2006 Massachusetts Institute of Technology
#
# This file is part of MIT/GNU Scheme.
#
# MIT/GNU Scheme is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# MIT/GNU Scheme is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with MIT/GNU Scheme; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
# 02111-1307, USA.

# Utility to set up an MIT/GNU Scheme build directory.
# The working directory must be the build directory.

. ../etc/functions.sh

../etc/Setup.sh "$@"

for FNS in `cd ../runtime; ls *.scm`; do
    FN="`basename ${FNS} .scm`.bin"
    maybe_link ${FN} ../runtime/${FN}
done

maybe_link runtime-unx.pkd ../runtime/runtime-unx.pkd

exit 0