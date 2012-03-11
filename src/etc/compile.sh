#!/bin/sh
#
# Copyright (C) 1986, 1987, 1988, 1989, 1990, 1991, 1992, 1993, 1994,
#     1995, 1996, 1997, 1998, 1999, 2000, 2001, 2002, 2003, 2004,
#     2005, 2006, 2007, 2008, 2009, 2010, 2011, 2012 Massachusetts
#     Institute of Technology
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
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
# 02110-1301, USA.

set -e

. etc/functions.sh

run_cmd "${@}"<<EOF
(begin
  (load "etc/compile.scm")
  (compile-cref compile-dir)
  (for-each compile-dir '("runtime" "star-parser" "sf")))
EOF

FASL=`get_fasl_file`
run_cmd_in_dir runtime ../microcode/scheme --batch-mode		\
	--library ../lib --fasl $FASL <<EOF
(disk-save "../lib/runtime.com")
EOF

# Syntax the new compiler in fresh (compiler) packages.  Use the new sf too.
run_cmd ./microcode/scheme --batch-mode --library lib --band runtime.com <<EOF
(begin
  (load-option 'SF)
  (with-working-directory-pathname "compiler/"
    (lambda () (load "compiler.sf"))))
EOF

run_cmd "${@}"<<EOF
(with-working-directory-pathname "compiler/"
  (lambda () (load "compiler.cbf")))
EOF

run_cmd ./microcode/scheme --batch-mode --library lib --band runtime.com <<EOF
(begin
  (load-option 'COMPILER)
  (load "etc/compile.scm")
  (compile-remaining-dirs compile-dir))
EOF
