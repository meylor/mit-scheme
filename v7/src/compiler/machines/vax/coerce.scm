#| -*-Scheme-*-

$Id: coerce.scm,v 1.5 1999/01/02 06:06:43 cph Exp $
$MC68020-Header: coerce.scm,v 1.10 88/08/31 05:56:37 GMT cph Exp $

Copyright (c) 1987, 1989, 1999 Massachusetts Institute of Technology

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
|#

;;;; Vax Specific Coercions

(declare (usual-integrations))

(define coerce-literal
  (standard-coercion
   (lambda (n)
     (if (<= 0 n 63)
	 n
	 (error "Bad short literal" n)))))

(define coerce-short-label
  (standard-coercion
   (lambda (offset)
     (or (if (negative? offset)
	     (and (>= offset -128) (+ offset 256))
	     (and (< offset 128) offset))
	 (error "Short label out of range" offset)))))

;; *** NOTE ***
;; If you add coercions here, remember to also add them in "insmac.scm".

(define make-coercion
  (coercion-maker
   `((UNSIGNED . ,coerce-unsigned-integer)
     (SIGNED . ,coerce-signed-integer))))

(define coerce-2-bit-unsigned (make-coercion 'UNSIGNED 2))
(define coerce-4-bit-unsigned (make-coercion 'UNSIGNED 4))
(define coerce-6-bit-unsigned (make-coercion 'UNSIGNED 6))
(define coerce-8-bit-unsigned (make-coercion 'UNSIGNED 8))
(define coerce-16-bit-unsigned (make-coercion 'UNSIGNED 16))
(define coerce-32-bit-unsigned (make-coercion 'UNSIGNED 32))

(define coerce-8-bit-signed (make-coercion 'SIGNED 8))
(define coerce-16-bit-signed (make-coercion 'SIGNED 16))
(define coerce-32-bit-signed (make-coercion 'SIGNED 32))
