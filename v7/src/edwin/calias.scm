;;; -*-Scheme-*-
;;;
;;;	$Header: /Users/cph/tmp/foo/mit-scheme/mit-scheme/v7/src/edwin/calias.scm,v 1.4 1989/04/05 18:15:52 cph Exp $
;;;
;;;	Copyright (c) 1986, 1989 Massachusetts Institute of Technology
;;;
;;;	This material was developed by the Scheme project at the
;;;	Massachusetts Institute of Technology, Department of
;;;	Electrical Engineering and Computer Science.  Permission to
;;;	copy this software, to redistribute it, and to use it for any
;;;	purpose is granted, subject to the following restrictions and
;;;	understandings.
;;;
;;;	1. Any copy made of this software must include this copyright
;;;	notice in full.
;;;
;;;	2. Users of this software agree to make their best efforts (a)
;;;	to return to the MIT Scheme project any improvements or
;;;	extensions that they make, so that these may be included in
;;;	future releases; and (b) to inform MIT of noteworthy uses of
;;;	this software.
;;;
;;;	3. All materials developed as a consequence of the use of this
;;;	software shall duly acknowledge such use, in accordance with
;;;	the usual standards of acknowledging credit in academic
;;;	research.
;;;
;;;	4. MIT has made no warrantee or representation that the
;;;	operation of this software will be error-free, and MIT is
;;;	under no obligation to provide any services, by way of
;;;	maintenance, update, or otherwise.
;;;
;;;	5. In conjunction with products arising from the use of this
;;;	material, there shall be no use of the name of the
;;;	Massachusetts Institute of Technology nor of any adaptation
;;;	thereof in any advertising, promotional, or sales literature
;;;	without prior written consent from MIT in each case.
;;;

;;;; Alias Characters

(declare (usual-integrations))

(define alias-characters '())

(define (define-alias-char char alias)
  (let ((entry (assq char alias-characters)))
    (if entry
	(set-cdr! entry alias)
	(set! alias-characters (cons (cons char alias) alias-characters))))
  unspecific)

(define (undefine-alias-char char)
  (set! alias-characters (del-assq! char alias-characters))
  unspecific)

(define (remap-alias-char char)
  (let ((entry (assq char alias-characters)))
    (cond (entry
	   (remap-alias-char (cdr entry)))
	  ((odd? (quotient (char-bits char) 2)) ;Control bit is set
	   (let ((code (char-code char))
		 (remap
		  (lambda (code)
		    (make-char code (- (char-bits char) 2)))))
	     (cond ((<= #x40 code #x5F) (remap (- code #x40)))
		   ((<= #x61 code #x7A) (remap (- code #x60)))
		   (else char))))
	  (else char))))

(define (unmap-alias-char char)
  (if (ascii-controlified? char)
      (unmap-alias-char
       (make-char (let ((code (char-code char)))
		    (+ code (if (<= #x01 code #x1A) #x60 #x40)))
		  (+ (char-bits char) 2)))
      (let ((entry
	     (list-search-positive alias-characters
	       (lambda (entry)
		 (eqv? (cdr entry) char)))))
	(if entry
	    (unmap-alias-char (car entry))
	    char))))

(define (ascii-controlified? char)
  (and (even? (quotient (char-bits char) 2))
       (let ((code (char-code char)))
	 (or (< code #x09)
	     (= code #x0B)
	     (if (< code #x1B)
		 (< #x0D code)
		 (and (< code #x20)
		      (< #x1B code)))))))
(define-integrable (char-name char)
  (char->name (unmap-alias-char char)))