#| -*-Scheme-*-

$Header: /Users/cph/tmp/foo/mit-scheme/mit-scheme/v7/src/runtime/output.scm,v 14.1 1988/06/13 11:48:42 cph Exp $

Copyright (c) 1988 Massachusetts Institute of Technology

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

;;;; Output
;;; package: (runtime output-port)

(declare (usual-integrations))

;;;; Output Ports

(define (initialize-package!)
  (set! *current-output-port* console-output-port)
  (set! beep (wrap-custom-operation-0 'BEEP))
  (set! clear (wrap-custom-operation-0 'CLEAR)))

(define (output-port/unparse state port)
  ((unparser/standard-method 'OUTPUT-PORT
			     (output-port/custom-operation port 'PRINT-SELF))
   state
   port))

(define-structure (output-port (conc-name output-port/)
			       (constructor %make-output-port)
			       (copier %output-port/copy)
			       (print-procedure output-port/unparse))
  state
  (operation/write-char false read-only true)
  (operation/write-string false read-only true)
  (operation/flush-output false read-only true)
  (custom-operations false read-only true))

(define (guarantee-output-port port)
  (if (not (output-port? port)) (error "Bad output port" port))
  port)

(define (output-port/custom-operation port name)
  (let ((entry (assq name (output-port/custom-operations port))))
    (and entry
	 (cdr entry))))

(define (output-port/copy port state)
  (let ((result (%output-port/copy port)))
    (set-output-port/state! result state)
    result))

(define (output-port/write-char port char)
  ((output-port/operation/write-char port) port char))

(define (output-port/write-string port string)
  ((output-port/operation/write-string port) port string))

(define (output-port/flush-output port)
  ((output-port/operation/flush-output port) port))

(define (output-port/x-size port)
  (or (let ((operation (output-port/custom-operation port 'X-SIZE)))
	(and operation
	     (operation port)))
      79))

(define (make-output-port operations state)
  (let ((operations
	 (map (lambda (entry)
		(cons (car entry) (cadr entry)))
	      operations)))
    (let ((operation
	   (lambda (name default)
	     (let ((entry (assq name operations)))
	       (if entry
		   (begin (set! operations (delq! entry operations))
			  (cdr entry))
		   (or default
		       (error "MAKE-OUTPUT-PORT: missing operation" name)))))))
      (let ((write-char (operation 'WRITE-CHAR false))
	    (write-string
	     (operation 'WRITE-STRING default-operation/write-string))
	    (flush-output
	     (operation 'FLUSH-OUTPUT default-operation/flush-output)))
	(%make-output-port state
			   write-char
			   write-string
			   flush-output
			   operations)))))

(define (default-operation/write-string port string)
  (let ((write-char (output-port/operation/write-char port))
	(end (string-length string)))
    (let loop ((index 0))
      (if (< index end)
	  (begin (write-char port (string-ref string index))
		 (loop (1+ index)))))))

(define (default-operation/flush-output port)
  port
  false)

(define *current-output-port*)

(define-integrable (current-output-port)
  *current-output-port*)

(define (with-output-to-port port thunk)
  (cond ((eq? port *current-output-port*) (thunk))
	((not (output-port? port)) (error "Bad output port" port))
	(else (fluid-let ((*current-output-port* port)) (thunk)))))

(define (with-output-to-file output-specifier thunk)
  (let ((new-port (open-output-file output-specifier))
	(old-port false))
    (dynamic-wind (lambda ()
		    (set! old-port *current-output-port*)
		    (set! *current-output-port* new-port)
		    (set! new-port false))
		  thunk
		  (lambda ()
		    (if *current-output-port*
			(close-output-port *current-output-port*))
		    (set! *current-output-port* old-port)
		    (set! old-port false)))))

(define (call-with-output-file output-specifier receiver)
  (let ((port (open-output-file output-specifier)))
    (let ((value (receiver port)))
      (close-output-port port)
      value)))

;;;; Output Procedures

(define (newline #!optional port)
  (let ((port
	 (if (default-object? port)
	     (current-output-port)
	     (guarantee-output-port port))))
    (output-port/write-char port #\Newline)
    (output-port/flush-output port))
  *the-non-printing-object*)

(define (write-char char #!optional port)
  (let ((port
	 (if (default-object? port)
	     (current-output-port)
	     (guarantee-output-port port))))
    (output-port/write-char port char)
    (output-port/flush-output port))
  *the-non-printing-object*)

(define (write-string string #!optional port)
  (let ((port
	 (if (default-object? port)
	     (current-output-port)
	     (guarantee-output-port port))))
    (output-port/write-string port string)
    (output-port/flush-output port))
  *the-non-printing-object*)

(define (close-output-port port)
  (let ((operation (output-port/custom-operation port 'CLOSE)))
    (if operation
	(operation port)))
  *the-non-printing-object*)

(define (wrap-custom-operation-0 operation-name)
  (lambda (#!optional port)
    (let ((port
	   (if (default-object? port)
	       (current-output-port)
	       (guarantee-output-port port))))
      (let ((operation (output-port/custom-operation port operation-name)))
	(if operation
	    (begin
	      (operation port)
	      (output-port/flush-output port)))))
    *the-non-printing-object*))

(define beep)
(define clear)

(define (display object #!optional port unparser-table)
  (let ((port
	 (if (default-object? port)
	     (current-output-port)
	     (guarantee-output-port port)))
	(unparser-table
	 (if (default-object? unparser-table)
	     (current-unparser-table)
	     (guarantee-unparser-table unparser-table))))
    (if (string? object)
	(output-port/write-string port object)
	(unparse-object/internal object port 0 false unparser-table))
    (output-port/flush-output port))
  *the-non-printing-object*)

(define (write object #!optional port unparser-table)
  (let ((port
	 (if (default-object? port)
	     (current-output-port)
	     (guarantee-output-port port)))
	(unparser-table
	 (if (default-object? unparser-table)
	     (current-unparser-table)
	     (guarantee-unparser-table unparser-table))))
    (unparse-object/internal object port 0 true unparser-table)
    (output-port/flush-output port))
  *the-non-printing-object*)

(define (write-line object #!optional port unparser-table)
  (let ((port
	 (if (default-object? port)
	     (current-output-port)
	     (guarantee-output-port port)))
	(unparser-table
	 (if (default-object? unparser-table)
	     (current-unparser-table)
	     (guarantee-unparser-table unparser-table))))
    (output-port/write-char port #\Newline)
    (unparse-object/internal object port 0 true unparser-table)
    (output-port/flush-output port))
  *the-non-printing-object*)