#| -*-Scheme-*-

$Id: toplev.scm,v 1.16 2001/12/17 17:40:58 cph Exp $

Copyright (c) 1988-2001 Massachusetts Institute of Technology

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
|#

;;;; Package Model: Top Level

(declare (usual-integrations))

(define (generate/common kernel)
  (lambda (filename)
    (let ((pathname (merge-pathnames filename)))
      (let ((pmodel (read-package-model pathname)))
	(let ((changes? (read-file-analyses! pmodel)))
	  (resolve-references! pmodel)
	  (kernel pathname pmodel changes?))))))

(define (cref/generate-trivial-constructor filename)
  (let ((pathname (merge-pathnames filename)))
    (write-external-descriptions pathname (read-package-model pathname) #f)))

(define cref/generate-cref
  (generate/common
   (lambda (pathname pmodel changes?)
     (write-cref pathname pmodel changes?))))

(define cref/generate-cref-unusual
  (generate/common
   (lambda (pathname pmodel changes?)
     (write-cref-unusual pathname pmodel changes?))))

(define cref/generate-constructors
  (generate/common
   (lambda (pathname pmodel changes?)
     (write-cref-unusual pathname pmodel changes?)
     (write-external-descriptions pathname pmodel changes?))))

(define cref/generate-all
  (generate/common
   (lambda (pathname pmodel changes?)
     (write-cref pathname pmodel changes?)
     (write-external-descriptions pathname pmodel changes?))))

(define (write-external-descriptions pathname pmodel changes?)
  (let ((package-set (package-set-pathname pathname)))
    (if (or changes?
	    (not (file-modification-time<?
		  (pathname-default-type pathname "pkg")
		  package-set)))
	(fasdump (construct-external-descriptions pmodel) package-set))))

(define (write-cref pathname pmodel changes?)
  (let ((cref-pathname
	 (pathname-new-type (package-set-pathname pathname) "crf")))
    (if (or changes?
	    (not (file-modification-time<?
		  (pathname-default-type pathname "pkg")
		  cref-pathname)))
	(with-output-to-file cref-pathname
	  (lambda ()
	    (format-packages pmodel))))))

(define (write-cref-unusual pathname pmodel changes?)
  (let ((cref-pathname
	 (pathname-new-type (package-set-pathname pathname) "crf")))
    (if (or changes?
	    (not (file-modification-time<?
		  (pathname-default-type pathname "pkg")
		  cref-pathname)))
	(with-output-to-file cref-pathname
	  (lambda ()
	    (format-packages-unusual pmodel))))))