#| -*-Scheme-*-

$Header: /Users/cph/tmp/foo/mit-scheme/mit-scheme/v7/src/compiler/etc/xcbfdir.scm,v 1.3 1990/10/10 02:03:40 jinx Rel $

Copyright (c) 1989, 1990 Massachusetts Institute of Technology

This material was developed by the Scheme project at the Massachusetts
Institute of Technology, Department of Electrical Engineering and
Computer Science.  Permission to copy this software, to redistribute
it, and to use it for any purpose is granted, subject to the following
restrictions and understandings.

1. Any copy made of this software must include this copyright notice
in full.

2. Users of this software agree to make their best efforts (a) to
return to the MIT Scheme project any improvements or extensions that
they make, so that these may be included in future releases; and (b)
to inform MIT of noteworthy uses of this software.

3. All materials developed as a consequence of the use of this
software shall duly acknowledge such use, in accordance with the usual
standards of acknowledging credit in academic research.

4. MIT has made no warrantee or representation that the operation of
this software will be error-free, and MIT is under no obligation to
provide any services, by way of maintenance, update, or otherwise.

5. In conjunction with products arising from the use of this material,
there shall be no use of the name of the Massachusetts Institute of
Technology nor of any adaptation thereof in any advertising,
promotional, or sales literature without prior written consent from
MIT in each case. |#

;;;; Distributed directory recompilation.

(declare (usual-integrations))

(define (process-directory directory processor extension)
  (for-each
   (lambda (pathname)
     (let ((one (pathname-new-type pathname extension))
	   (two (pathname-new-type pathname "touch")))
       (call-with-current-continuation
	(lambda (here)
	  (bind-condition-handler
	   '()
	   (lambda (condition)
	     (newline)
	     (display ";; *** Aborting ")
	     (display pathname)
	     (display " ***")
	     (newline)
	     (condition/write-report condition)
	     (newline)
	     (here 'next))
	   (lambda ()
	     (let ((touch-created-file?))
	       (dynamic-wind
		(lambda ()
		  ;; file-touch returns #T if the file did not exist,
		  ;; it returns #F if it did.
		  (set! touch-created-file?
			(file-touch two)))
		(lambda ()
		  (if (and touch-created-file?
			   (let ((one-time (file-modification-time one)))
			     (or (not one-time)
				 (< one-time
				    (file-modification-time pathname)))))
		      (processor pathname)))
		(lambda ()
		  (if touch-created-file?
		      (delete-file two)))))))))))
   (directory-read
    (merge-pathnames (pathname-as-directory (->pathname directory))
		     (->pathname "*.bin")))))

(define (recompile-directory dir)
  (process-directory dir compile-bin-file "com"))

(define (cross-compile-directory dir)
  (process-directory dir cross-compile-bin-file "bits.x"))