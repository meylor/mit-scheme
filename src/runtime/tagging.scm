#| -*-Scheme-*-

Copyright (C) 1986, 1987, 1988, 1989, 1990, 1991, 1992, 1993, 1994,
    1995, 1996, 1997, 1998, 1999, 2000, 2001, 2002, 2003, 2004, 2005,
    2006, 2007, 2008, 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2016,
    2017 Massachusetts Institute of Technology

This file is part of MIT/GNU Scheme.

MIT/GNU Scheme is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at
your option) any later version.

MIT/GNU Scheme is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with MIT/GNU Scheme; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301,
USA.

|#

;;;; Tagged objects
;;; package: (runtime tagging)

(declare (usual-integrations))

;;; TODO(cph): eliminate after 9.3 release:
(define tagged-object-type #x25)

(define (tagged-object? object)
  (fix:= (object-type object) tagged-object-type))

(define (object-tagger predicate)
  (let ((tag (predicate->tag predicate)))
    (lambda (datum)
      (make-tagged-object tag datum))))

(define (tag-object predicate datum)
  (make-tagged-object (predicate->tag predicate) datum))

(define (tagged-object-predicate object)
  (tag->predicate (tagged-object-tag object)))

(define-integrable (make-tagged-object tag datum)
  (system-pair-cons tagged-object-type tag datum))

(define (tagged-object-tag object)
  (guarantee tagged-object? object 'tagged-object-tag)
  (system-pair-car object))

(define (tagged-object-datum object)
  (guarantee tagged-object? object 'tagged-object-datum)
  (system-pair-cdr object))

(define unparser-methods)
(define (initialize-package!)
  (register-predicate! tagged-object? 'tagged-object)
  (set! unparser-methods (make-key-weak-eqv-hash-table))
  unspecific)

(define (get-tagged-object-unparser-method object)
  (hash-table-ref/default unparser-methods (tagged-object-tag object) #f))

(define (set-tagged-object-unparser-method! tag unparser)
  (if unparser
      (begin
	(guarantee-unparser-method unparser 'set-tagged-object-unparser-method!)
	(hash-table-set! unparser-methods tag unparser))
      (hash-table-delete! unparser-methods tag)))