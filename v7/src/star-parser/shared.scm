;;; -*-Scheme-*-
;;;
;;; $Id: shared.scm,v 1.9 2001/07/14 11:42:35 cph Exp $
;;;
;;; Copyright (c) 2001 Massachusetts Institute of Technology
;;;
;;; This program is free software; you can redistribute it and/or
;;; modify it under the terms of the GNU General Public License as
;;; published by the Free Software Foundation; either version 2 of the
;;; License, or (at your option) any later version.
;;;
;;; This program is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;; General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with this program; if not, write to the Free Software
;;; Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
;;; 02111-1307, USA.

;;;; Shared code for matchers and parsers

(declare (usual-integrations))

(define (with-buffer-name thunk)
  (let ((v (generate-uninterned-symbol)))
    `(LAMBDA (,v)
       ,(fluid-let ((*buffer-name* v))
	  (thunk)))))

(define *buffer-name*)

(define (with-variable-bindings expressions receiver)
  (let ((variables
	 (map (lambda (x) x (generate-uninterned-symbol))
	      expressions)))
    (maybe-make-let (map list variables expressions)
		    (apply receiver variables))))

(define (with-variable-binding expression receiver)
  (with-variable-bindings (list expression) receiver))

(define (maybe-make-let bindings body)
  (if (pair? bindings)
      `(LET ,bindings ,body)
      body))

(define (check-1-arg expression #!optional predicate)
  (if (and (pair? (cdr expression))
	   (null? (cddr expression))
	   (or (default-object? predicate)
	       (predicate expression)))
      (cadr expression)
      (error "Malformed expression:" expression)))

(define (check-2-args expression #!optional predicate)
  (if (not (and (pair? (cdr expression))
		(pair? (cddr expression))
		(null? (cdddr expression))
		(or (default-object? predicate)
		    (predicate expression))))
      (error "Malformed expression:" expression)))

(define (handle-complex-expression expression bindings)
  (if (or (char? expression)
	  (string? expression)
	  (symbol? expression))
      expression
      (let loop ((bindings* (cdr bindings)))
	(if (pair? bindings*)
	    (if (equal? expression (caar bindings*))
		(cdar bindings*)
		(loop (cdr bindings*)))
	    (let ((variable (generate-uninterned-symbol)))
	      (set-cdr! bindings
			(cons (cons expression variable)
			      (cdr bindings)))
	      variable)))))

(define (named-lambda-bvl? object)
  (and (pair? object)
       (symbol? (car object))
       (let loop ((object (cdr object)))
	 (or (null? object)
	     (symbol? object)
	     (and (pair? object)
		  (symbol? (car object))
		  (loop (cdr object)))))))

(define parser-macros-rtd
  (make-record-type "parser-macros" '(PARENT MATCHER-TABLE PARSER-TABLE)))

(define make-parser-macros
  (let ((constructor (record-constructor parser-macros-rtd)))
    (lambda (parent)
      (if parent (guarantee-parser-macros parent 'MAKE-PARSER-MACROS))
      (constructor (or parent *global-parser-macros*)
		   (make-eq-hash-table)
		   (make-eq-hash-table)))))

(define *global-parser-macros*
  ((record-constructor parser-macros-rtd)
   #f
   (make-eq-hash-table)
   (make-eq-hash-table)))

(define (guarantee-parser-macros object procedure)
  (if (not (parser-macros? object))
      (error:wrong-type-argument object "parser macros" procedure)))

(define parser-macros?
  (record-predicate parser-macros-rtd))

(define parent-macros
  (record-accessor parser-macros-rtd 'PARENT))

(define matcher-macros-table
  (record-accessor parser-macros-rtd 'MATCHER-TABLE))

(define parser-macros-table
  (record-accessor parser-macros-rtd 'PARSER-TABLE))

(define (define-matcher-macro name expander)
  (hash-table/put! (matcher-macros-table *parser-macros*) name expander))

(define (lookup-matcher-macro name)
  (let loop ((environment *parser-macros*))
    (and environment
	 (or (hash-table/get (matcher-macros-table environment) name #f)
	     (loop (parent-macros environment))))))

(define (define-parser-macro name expander)
  (hash-table/put! (parser-macros-table *parser-macros*) name expander))

(define (lookup-parser-macro name)
  (let loop ((environment *parser-macros*))
    (and environment
	 (or (hash-table/get (parser-macros-table environment) name #f)
	     (loop (parent-macros environment))))))

(define (with-current-parser-macros macros thunk)
  (guarantee-parser-macros macros 'WITH-CURRENT-PARSER-MACROS)
  (fluid-let ((*parser-macros* macros))
    (thunk)))

(define (current-parser-macros)
  *parser-macros*)

(define (set-current-parser-macros! macros)
  (guarantee-parser-macros macros 'SET-CURRENT-PARSER-MACROS!)
  (set! *parser-macros* macros)
  unspecific)

(define (global-parser-macros)
  *global-parser-macros*)

(define *parser-macros*
  *global-parser-macros*)

;;;; Buffer pointers

(define (call-with-unknown-pointer procedure)
  (let ((v.u (cons (generate-uninterned-symbol) #f)))
    (let ((x (procedure (cons v.u #f))))
      (if (cdr v.u)
	  `(LET ((,(car v.u) (GET-PARSER-BUFFER-POINTER ,*buffer-name*)))
	     ,x)
	  x))))

(define (backtrack-to backtrack-pointer pointer)
  ;; Specify that we want to backtrack to the position specified in
  ;; BACKTRACK-POINTER.  But don't actually change the position yet.
  ;; Instead delay the move until it's actually needed.  Without the
  ;; delay, we can generate multiple sequential calls to change the
  ;; position, which is wasteful since only the last call in the
  ;; sequence is meaningful.
  (cons (car pointer)
	(let ((p (or (cdr backtrack-pointer) (car backtrack-pointer))))
	  (if (eq? (car pointer) p)
	      #f
	      p))))

(define (handle-pending-backtracking pointer procedure)
  ;; Perform a pending backtracking operation, if any.
  (if (cdr pointer)
      (begin
	(set-cdr! (cdr pointer) #t)
	`(BEGIN
	   (SET-PARSER-BUFFER-POINTER! ,*buffer-name* ,(car (cdr pointer)))
	   ,(procedure (cons (cdr pointer) #f))))
      (procedure (cons (car pointer) #f))))

(define (simple-backtracking-continuation value)
  (lambda (pointer)
    (handle-pending-backtracking pointer
      (lambda (pointer)
	pointer
	value))))

(define (pointer-reference pointer)
  (let ((p (or (cdr pointer) (car pointer))))
    (set-cdr! p #t)
    (car p)))

;;;; Code optimizer

(define (optimize-expression expression)
  (let loop ((entries optimizer-patterns))
    (cond ((pair? entries)
	   (if (and (syntax-match? (caar entries) expression)
		    (or (not (cadar entries))
			((cadar entries) expression)))
	       (let ((expression* ((cddar entries) expression)))
		 (if (equal? expression* expression)
		     expression
		     (optimize-expression expression*)))
	       (loop (cdr entries))))
	  ((and (pair? expression)
		(symbol? (car expression)))
	   (let ((expression*
		  (let ((optimizer
			 (hash-table/get default-optimizers
					 (car expression)
					 #f)))
		    (if optimizer
			(optimizer expression)
			(cons (car expression)
			      (map optimize-expression (cdr expression)))))))
	     (if (equal? expression* expression)
		 expression
		 (optimize-expression expression*))))
	  (else expression))))

(define (define-optimizer pattern predicate optimizer)
  (let ((entry (assoc pattern optimizer-patterns))
	(datum (cons predicate optimizer)))
    (if entry
	(set-cdr! entry datum)
	(begin
	  (set! optimizer-patterns
		(cons (cons pattern datum) optimizer-patterns))
	  unspecific))))

(define optimizer-patterns
  '())

(define (define-default-optimizer keyword optimizer)
  (hash-table/put! default-optimizers keyword optimizer)
  keyword)

(define default-optimizers
  (make-eq-hash-table))

(define (predicate-not-or expression)
  (not (and (pair? (cadr expression))
	    (eq? (caadr expression) 'OR))))

(define-optimizer '('IF EXPRESSION #T #F) predicate-not-or
  (lambda (expression)
    (cadr expression)))

(define-optimizer '('IF EXPRESSION #F #T) predicate-not-or
  (lambda (expression)
    `(NOT ,(cadr expression))))

(define-optimizer '('IF EXPRESSION EXPRESSION #F)
    (lambda (expression)
      (not (eq? (caddr expression) '#T)))
  (lambda (expression)
    `(AND ,(cadr expression) ,(caddr expression))))

(define-optimizer '('IF EXPRESSION #F EXPRESSION)
    (lambda (expression)
      (not (eq? (cadddr expression) '#T)))
  (lambda (expression)
    `(AND (NOT ,(cadr expression)) ,(cadddr expression))))

(define-optimizer '('IF EXPRESSION EXPRESSION EXPRESSION)
    (lambda (expression)
      (equal? (caddr expression) (cadddr expression)))
  (lambda (expression)
    `(BEGIN ,(cadr expression) ,(caddr expression))))

(define-optimizer '('IF EXPRESSION EXPRESSION 'UNSPECIFIC) #f
  (lambda (expression)
    `(IF ,(cadr expression) ,(caddr expression))))

(define-optimizer '('IF EXPRESSION EXPRESSION)
    (lambda (expression)
      (and (eq? (caddr expression) 'UNSPECIFIC)
	   (predicate-not-or expression)))
  (lambda (expression)
    (cadr expression)))

(define-optimizer '('IF EXPRESSION
			('IF EXPRESSION EXPRESSION EXPRESSION)
			EXPRESSION)
    (lambda (expression)
      (equal? (cadddr (caddr expression))
	      (cadddr expression)))
  (lambda (expression)
    `(IF (AND ,(cadr expression) ,(cadr (caddr expression)))
	 ,(caddr (caddr expression))
	 ,(cadddr expression))))

(define-optimizer '('IF EXPRESSION
			EXPRESSION
			('IF EXPRESSION EXPRESSION EXPRESSION))
    (lambda (expression)
      (equal? (caddr (cadddr expression))
	      (caddr expression)))
  (lambda (expression)
    `(IF (OR ,(cadr expression) ,(cadr (cadddr expression)))
	 ,(caddr expression)
	 ,(cadddr (cadddr expression)))))

(define-optimizer '('IF EXPRESSION
			('BEGIN . (+ EXPRESSION))
			EXPRESSION)
    (lambda (expression)
      (let ((expression* (car (last-pair (caddr expression)))))
	(and (syntax-match? '('IF EXPRESSION EXPRESSION EXPRESSION)
			    expression*)
	     (equal? (cadddr expression*)
		     (cadddr expression)))))
  (lambda (expression)
    (let ((expression* (car (last-pair (caddr expression)))))
      `(IF (AND ,(cadr expression)
		(BEGIN ,@(except-last-pair (cdr (caddr expression)))
		       ,(cadr expression*)))
	   ,(caddr expression*)
	   ,(cadddr expression)))))

(define-optimizer '('IF EXPRESSION
			EXPRESSION
			('BEGIN . (+ EXPRESSION)))
    (lambda (expression)
      (let ((expression* (car (last-pair (cadddr expression)))))
	(and (syntax-match? '('IF EXPRESSION EXPRESSION EXPRESSION)
			    expression*)
	     (equal? (caddr expression*)
		     (caddr expression)))))
  (lambda (expression)
    (let ((expression* (car (last-pair (cadddr expression)))))
      `(IF (OR ,(cadr expression)
	       (BEGIN ,@(except-last-pair (cdr (cadddr expression)))
		      ,(cadr expression*)))
	   ,(caddr expression)
	   ,(cadddr expression*)))))

(define-optimizer '('IF EXPRESSION
			('OR . (+ EXPRESSION))
			EXPRESSION)
    (lambda (expression)
      (equal? (car (last-pair (caddr expression)))
	      (cadddr expression)))
  (lambda (expression)
    `(OR (AND ,(cadr expression)
	      (OR ,@(except-last-pair (cdr (caddr expression)))))
	 ,(cadddr expression))))

(define-optimizer '('LET ((IDENTIFIER EXPRESSION))
		     ('IF IDENTIFIER
			  IDENTIFIER
			  EXPRESSION))
    (lambda (expression)
      (and (eq? (caar (cadr expression))
		(cadr (caddr expression)))
	   (eq? (caddr (caddr expression))
		(cadr (caddr expression)))))
  (lambda (expression)
    `(OR ,(cadar (cadr expression))
	 ,(cadddr (caddr expression)))))

(define-optimizer '('LET ((IDENTIFIER EXPRESSION))
		     ('AND IDENTIFIER
			   IDENTIFIER))
    (lambda (expression)
      (and (eq? (caar (cadr expression))
		(cadr (caddr expression)))
	   (eq? (caddr (caddr expression))
		(cadr (caddr expression)))))
  (lambda (expression)
    (cadar (cadr expression))))

(define-default-optimizer 'LET
  (lambda (expression)
    (if (symbol? (cadr expression))
	`(LET ,(cadr expression)
	   ,(map (lambda (binding)
		   `(,(car binding) ,(optimize-expression (cadr binding))))
		 (caddr expression))
	   ,@(map optimize-expression (cdddr expression)))
	`(LET ,(map (lambda (binding)
		      `(,(car binding) ,(optimize-expression (cadr binding))))
		    (cadr expression))
	   ,@(map optimize-expression (cddr expression))))))

(define-optimizer '(('LAMBDA (* IDENTIFIER) . (* EXPRESSION)) . (* EXPRESSION))
    (lambda (expression)
      (= (length (cadr (car expression)))
	 (length (cdr expression))))
  (lambda (expression)
    `(LET ,(map (lambda (v x) (list v x))
		(cadr (car expression))
		(map optimize-expression (cdr expression)))
       ,@(map optimize-expression (cddr (car expression))))))

(define-optimizer '('LAMBDA (* IDENTIFIER) EXPRESSION) #f
  (lambda (expression)
    `(LAMBDA ,(cadr expression) ,(optimize-expression (caddr expression)))))

(define-default-optimizer 'LAMBDA
  (lambda (expression)
    `(LAMBDA ,(cadr expression)
       ,@(map optimize-expression (cddr expression)))))

(define-optimizer '('VECTOR-MAP EXPRESSION ('VECTOR EXPRESSION)) #f
  (lambda (expression)
    `(VECTOR (,(cadr expression) ,(cadr (caddr expression))))))

(define-optimizer '('VECTOR-MAP IDENTIFIER ('VECTOR . (* EXPRESSION))) #f
  (lambda (expression)
    `(VECTOR
      ,@(map (lambda (subexpression)
	       `(,(cadr expression) ,subexpression))
	     (cdr (caddr expression))))))

(define-optimizer '('NOT EXPRESSION) #f
  (lambda (expression)
    `(NOT ,(optimize-expression (cadr expression)))))

(define-optimizer '('VECTOR-APPEND . (* EXPRESSION)) #f
  (lambda (expression)
    (optimize-group-expression expression '(VECTOR))))

(define-optimizer '('AND . (* EXPRESSION)) #f
  (lambda (expression)
    (optimize-group-expression expression '#T)))

(define-optimizer '('OR . (* EXPRESSION)) #f
  (lambda (expression)
    (optimize-group-expression expression '#F)))

(define-optimizer '('BEGIN . (+ EXPRESSION)) #f
  (lambda (expression)
    (optimize-group-expression expression 'UNSPECIFIC)))

(define (optimize-group-expression expression identity)
  (let loop
      ((expressions
	(delete identity
		(map optimize-expression
		     (flatten-subexpressions expression)))))
    (if (pair? expressions)
	(if (pair? (cdr expressions))
	    `(,(car expression) ,@expressions)
	    (car expressions))
	identity)))

(define (flatten-subexpressions expression)
  (flatten-expressions (cdr expression) (car expression)))

(define (flatten-expressions expressions keyword)
  (let loop ((expressions expressions))
    (if (pair? expressions)
	(if (and (pair? (car expressions))
		 (eq? (caar expressions) keyword))
	    (loop (append (cdar expressions) (cdr expressions)))
	    (cons (car expressions) (loop (cdr expressions))))
	'())))

;;; Edwin Variables:
;;; Eval: (scheme-indent-method 'define-optimizer 2)
;;; End: