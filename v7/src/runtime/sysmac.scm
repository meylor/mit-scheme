#| -*-Scheme-*-

$Header: /Users/cph/tmp/foo/mit-scheme/mit-scheme/v7/src/runtime/sysmac.scm,v 14.1 1988/05/20 01:03:06 cph Exp $

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

;;;; System Internal Syntax
;;; package: system-macros-package

(declare (usual-integrations))

(define (initialize-package!)
  (set! syntax-table/system-internal (make-system-internal-syntax-table)))

(define syntax-table/system-internal)

(define (make-system-internal-syntax-table)
  (let ((table (make-syntax-table system-global-syntax-table)))
    (for-each (lambda (entry)
		(syntax-table-define table (car entry) (cadr entry)))
	      `((DEFINE-INTEGRABLE ,transform/define-integrable)
		(DEFINE-PRIMITIVES ,transform/define-primitives)
		(UCODE-PRIMITIVE ,transform/ucode-primitive)
		(UCODE-RETURN-ADDRESS ,transform/ucode-return-address)
		(UCODE-TYPE ,transform/ucode-type)))
    table))

(define transform/define-primitives
  (macro names
    `(BEGIN ,@(map (lambda (name)
		     (cond ((not (pair? name))
			    (primitive-definition name (list name)))
			   ((not (symbol? (cadr name)))
			    (primitive-definition (car name) name))
			   (else
			    (primitive-definition (car name) (cdr name)))))
		   names))))

(define (primitive-definition variable-name primitive-args)
  `(DEFINE-INTEGRABLE ,variable-name
     ,(apply make-primitive-procedure primitive-args)))

(define transform/ucode-type
  (macro arguments
    (apply microcode-type arguments)))

(define transform/ucode-primitive
  (macro arguments
    (apply make-primitive-procedure arguments)))

(define transform/ucode-return-address
  (macro arguments
    (make-return-address (apply microcode-return arguments))))

(define transform/define-integrable
  (macro (pattern . body)
    (parse-define-syntax pattern body
      (lambda (name body)
	`(BEGIN (DECLARE (INTEGRATE ,pattern))
		(DEFINE ,name ,@body)))
      (lambda (pattern body)
	`(BEGIN (DECLARE (INTEGRATE-OPERATOR ,(car pattern)))
		(DEFINE ,pattern
		  ,@(if (list? (cdr pattern))
			`((DECLARE
			   (INTEGRATE
			    ,@(lambda-list->bound-names (cdr pattern)))))
			'())
		  ,@body))))))

(define (parse-define-syntax pattern body if-variable if-lambda)
  (cond ((pair? pattern)
	 (let loop ((pattern pattern) (body body))
	   (cond ((pair? (car pattern))
		  (loop (car pattern) `((LAMBDA ,(cdr pattern) ,@body))))
		 ((symbol? (car pattern))
		  (if-lambda pattern body))
		 (else
		  (error "Illegal name" (car pattern))))))
	((symbol? pattern)
	 (if-variable pattern body))
	(else
	 (error "Illegal name" pattern))))

(define (lambda-list->bound-names lambda-list)
  (cond ((null? lambda-list)
	 '())
	((pair? lambda-list)
	 (let ((lambda-list
		(if (eq? (car lambda-list) lambda-optional-tag)
		    (begin (if (not (pair? (cdr lambda-list)))
			       (error "Missing optional variable" lambda-list))
			   (cdr lambda-list))
		    lambda-list)))
	   (cons (let ((parameter (car lambda-list)))
		   (if (pair? parameter) (car parameter) parameter))
		 (lambda-list->bound-names (cdr lambda-list)))))
	(else
	 (if (not (symbol? lambda-list))
	     (error "Illegal rest variable" lambda-list))
	 (list lambda-list))))