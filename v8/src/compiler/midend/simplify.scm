#| -*-Scheme-*-

$Id: simplify.scm,v 1.4 1995/02/11 03:16:45 adams Exp $

Copyright (c) 1994 Massachusetts Institute of Technology

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

;;;; Substitute simple and used-only-once parameters
;;; package: (compiler midend)

(declare (usual-integrations))

(define (simplify/top-level program)
  (simplify/expr #F program))

(define-macro (define-simplifier keyword bindings . body)
  (let ((proc-name (symbol-append 'SIMPLIFY/ keyword)))
    (call-with-values
	(lambda () (%matchup (cdr bindings) '(handler env) '(cdr form)))
      (lambda (names code)
	`(DEFINE ,proc-name
	   (LET ((HANDLER (LAMBDA ,(cons (car bindings) names) ,@body)))
	     (NAMED-LAMBDA (,proc-name ENV FORM)
	       (LET ((TRANSFORM-CODE (LAMBDA () ,code)))
		 (LET ((INFO (SIMPLIFY/GET-DBG-INFO ENV FORM)))
		   (LET ((CODE (TRANSFORM-CODE)))
		     (IF INFO
			 (CODE-REWRITE/REMEMBER* CODE INFO))
		     CODE))))))))))

(define-simplifier LOOKUP (env name)
  (let ((ref `(LOOKUP ,name)))
    (simplify/lookup*! env name ref 'ORDINARY)))

(define-simplifier LAMBDA (env lambda-list body)
  `(LAMBDA ,lambda-list
     ,(simplify/expr
       (simplify/env/make env
	(lmap simplify/binding/make (lambda-list->names lambda-list)))
       body)))

(define-simplifier QUOTE (env object)
  env					; ignored
  `(QUOTE ,object))

(define-simplifier DECLARE (env #!rest anything)
  env					; ignored
  `(DECLARE ,@anything))

(define-simplifier BEGIN (env #!rest actions)
  `(BEGIN ,@(simplify/expr* env actions)))

(define-simplifier IF (env pred conseq alt)
  `(IF ,(simplify/expr env pred)
       ,(simplify/expr env conseq)
       ,(simplify/expr env alt)))

(define (do-simplification env mutually-recursive? bindings body continue)
  ;; BINDINGS is a list of triples: (environment name expression)
  ;; where ENVIRONMENT is either #F or the environment for the lambda
  ;; expression bound to this name
  (define unsafe-cyclic-reference?
    (if mutually-recursive?
	(let ((finder (association-procedure eq? second)))
	  (make-breaks-cycle? (map second bindings)
			      (lambda (name)
				(let* ((triple (finder name bindings))
				       (env    (first triple)))
				  (if env
				      (simplify/env/free-calls env)
				      '())))))
	(lambda (lambda-expr) lambda-expr #F)))

  (simplify/bindings env unsafe-cyclic-reference?
		     (simplify/delete-parameters env bindings
						 unsafe-cyclic-reference?)
		     body continue))

(define-simplifier CALL (env rator cont #!rest rands)
  (define (do-ops rator*)
    `(CALL ,rator*
	   ,(simplify/expr env cont)
	   ,@(simplify/expr* env rands)))

  (cond ((LOOKUP/? rator)
	 (let* ((name   (lookup/name rator))
		(rator* (simplify/remember `(LOOKUP ,name) rator))
		(result (do-ops rator*)))
	   (simplify/lookup*! env name result 'OPERATOR)))
	((LAMBDA/? rator)
	 (guarantee-simple-lambda-list (lambda/formals rator)) ;Miller & Adams
	 (let* ((lambda-list (lambda/formals rator))
		(env0  (simplify/env/make env
			 (lmap simplify/binding/make lambda-list)))
		(body* (simplify/expr env0 (caddr rator)))
		(bindings* (map (lambda (name value)
				  (simplify/binding&value env name value))
				lambda-list
				(cons cont rands))))
	   (do-simplification env0 #F bindings* body*
	     (lambda (bindings* body*)
	       (simplify/pseudo-letify rator bindings* body*)))))
	(else
	 (do-ops (simplify/expr env rator)))))

(define-simplifier LET (env bindings body)
  (let* ((env0 (simplify/env/make env
		(lmap (lambda (binding) (simplify/binding/make (car binding)))
		      bindings)))
	 (body* (simplify/expr env0 body))
	 (bindings*
	  (lmap (lambda (binding)
		  (simplify/binding&value env (car binding) (cadr binding)))
		bindings)))
    (do-simplification env0 #F bindings* body* simplify/letify)))

(define-simplifier LETREC (env bindings body)
  (let* ((env0 (simplify/env/make env
		(lmap (lambda (binding) (simplify/binding/make (car binding)))
		      bindings)))
	 (body* (simplify/expr env0 body))
	 (bindings*
	  (lmap (lambda (binding)
		  (simplify/binding&value env0 (car binding) (cadr binding)))
		bindings)))
    (do-simplification env0 #T bindings* body* simplify/letrecify)))

(define (simplify/binding&value env name value)
  (if (not (LAMBDA/? value))
      (list false name (simplify/expr env value))
      (let* ((lambda-list (lambda/formals value))
	     (env1 (simplify/env/make env
		    (lmap simplify/binding/make
			  (lambda-list->names lambda-list)))))
	(let ((value*
	       `(LAMBDA ,lambda-list
		  ,(simplify/expr env1 (lambda/body value)))))
	  (list env1 name (simplify/remember value* value))))))

(define (simplify/delete-parameters env0 bindings unsafe-cyclic-reference?)
  ;; ENV0 is the current environment frame
  ;; BINDINGS is parallel to that, but is a list of
  ;;   (frame* name expression) triplet lists as returned by
  ;;   simplify/binding&value, where frame* is either #F or the frame
  ;;   for the LAMBDA expression that is bound to this name
  (for-each
      (lambda (bnode triplet)
	(let ((env1  (first triplet))
	      (name  (second triplet))
	      (value (third triplet)))
	  (and env1
	       (null? (simplify/binding/ordinary-refs bnode))
	       (not (null? (simplify/binding/operator-refs bnode)))
	       ;; Don't bother if it will be open coded
	       (not (null? (cdr (simplify/binding/operator-refs bnode))))
	       (not (simplify/open-code? name value unsafe-cyclic-reference?))
	       ;; At this point, env1 and triplet represent a LAMBDA
	       ;; expression to which there are no regular references and
	       ;; which will not be open coded.  We consider altering its
	       ;; formal parameter list.
	       (let ((unrefd
		      (list-transform-positive (simplify/env/bindings env1)
			(lambda (bnode*)
			  (and (null? (simplify/binding/ordinary-refs bnode*))
			       (null? (simplify/binding/operator-refs bnode*))
			       (not (continuation-variable?
				     (simplify/binding/name bnode*))))))))
		 (and (not (null? unrefd))
		      (for-each (lambda (unrefd)
				  (simplify/maybe-delete unrefd
							 bnode
							 (caddr triplet)))
			unrefd))))))
    (simplify/env/bindings env0)
    bindings)
  (lmap cdr bindings))

(define (simplify/maybe-delete unrefd bnode form)
  (let ((position (simplify/operand/position unrefd form))
	(operator-refs (simplify/binding/operator-refs bnode)))
    (and (positive? position)		; continuation/ignore must remain
	 (if (for-all? operator-refs
	       (lambda (call)
		 (simplify/deletable-operand? call position)))
	     (begin
	       (for-each
		(lambda (call)
		  (simplify/delete-operand! call position))
		operator-refs)
	       (simplify/delete-parameter! form position))))))

(define (simplify/operand/position bnode* form)
  (let ((name (simplify/binding/name bnode*)))
    (let loop ((ll (cadr form))
	       (index 0))
      (cond ((null? ll)
	     (internal-error "Missing operand" name form))
	    ((eq? name (car ll)) index)
	    ((or (eq? (car ll) '#!OPTIONAL)
		 (eq? (car ll) '#!REST))
	     -1)
	    (else
	     (loop (cdr ll) (+ index 1)))))))

(define (simplify/deletable-operand? call position)
  (let loop ((rands    (call/cont-and-operands call))
	     (position position))
    (and (not (null? rands))
	 (if (zero? position)
	     (form/simple&side-effect-free? (car rands))
	     (loop (cdr rands) (- position 1))))))

(define (simplify/delete-operand! call position)
  (form/rewrite!
   call
   `(CALL ,(call/operator call)
	  ,@(list-delete/index (call/cont-and-operands call) position))))

(define (simplify/delete-parameter! form position)
  (set-car! (cdr form)
	    (list-delete/index (cadr form) position)))

(define (list-delete/index l index)
  (let loop ((l l)
	     (index index)
	     (accum '()))
    (if (zero? index)
	(append (reverse accum) (cdr l))
	(loop (cdr l)
	      (- index 1)
	      (cons (car l) accum)))))

(define (simplify/bindings env0 unsafe-cyclic-reference? bindings body letify)
  ;; ENV0 is the current environment frame
  ;; BINDINGS is parallel to that, but is a list of
  ;;   (name expression) two-lists as returned by
  ;;   simplify/delete-parameters
  (let* ((frame-bindings (simplify/env/bindings env0))
	 (unused
	  (list-transform-positive frame-bindings
	    (lambda (binding)
	      (and (null? (simplify/binding/ordinary-refs binding))
		   (null? (simplify/binding/operator-refs binding)))))))
    (call-with-values
     (lambda ()
       (list-split unused
		   (lambda (binding)
		     (let* ((place (assq (simplify/binding/name binding)
					 bindings)))
		       (form/simple&side-effect-free? (cadr place))))))
     (lambda (simple-unused hairy-unused)
       ;; simple-unused can be flushed, since they have no side effects
       (let ((bindings* (delq* (lmap (lambda (simple)
				       (assq (simplify/binding/name simple)
					     bindings))
				     simple-unused)
			       bindings))
	     (not-simple-unused (delq* simple-unused frame-bindings)))
	 (if (or (not (eq? *order-of-argument-evaluation* 'ANY))
		 (null? hairy-unused))
	     (let ((new-env
		    (simplify/env/modified-copy env0 not-simple-unused)))
	       (simplify/bindings* new-env
				   bindings*
				   unsafe-cyclic-reference?
				   body
				   letify))
	     (let ((hairy-bindings
		    (lmap (lambda (hairy)
			    (assq (simplify/binding/name hairy)
				  bindings*))
			  hairy-unused))
		   (used-bindings (delq* hairy-unused not-simple-unused)))
	       (beginnify
		(append
		 (map cadr hairy-bindings)
		 (list
		  (let ((new-env
			 (simplify/env/modified-copy env0 used-bindings)))
		    (simplify/bindings* new-env
					(delq* hairy-bindings bindings*)
					unsafe-cyclic-reference?
					body
					letify))))))))))))

(define (simplify/bindings* env0 bindings unsafe-cyclic-reference? body letify)
  ;; ENV0 is the current environment frame, as simplified by simplify/bindings
  ;; BINDINGS is parallel to that, but is a list of
  ;;   (name expression) two-lists as returned by
  ;;   simplify/delete-parameters
  (let* ((frame-bindings (simplify/env/bindings env0))
	 (to-substitute
	  (list-transform-positive frame-bindings
	   (lambda (node)
	     (let* ((name  (simplify/binding/name node))
		    (value (second (assq name bindings))))
	       (and (pair? value)
		    (let ((ordinary (simplify/binding/ordinary-refs node))
			  (operator (simplify/binding/operator-refs node)))
		      (if (LAMBDA/? value)
			  (or (and (null? ordinary)
				   (or (null? (cdr operator))
				       (simplify/open-code?
					name value unsafe-cyclic-reference?)))
			      (and (null? operator)
				   (null? (cdr ordinary))))
			  (and (= (+ (length ordinary) (length operator)) 1)
			       (simplify/substitute? value body))))))))))
    (for-each
     (lambda (node)
       (simplify/substitute! node
			     (cadr (assq (simplify/binding/name node)
					 bindings))))
     to-substitute)
    ;; This works only as long as all references are replaced.
    (letify (delq* (lmap (lambda (node)
			   (assq (simplify/binding/name node)
				 bindings))
			 to-substitute)
		   bindings)
	    body)))

(define (simplify/substitute? value body)
  (or (form/simple&side-effect-insensitive? value)
      (and *after-cps-conversion?*
	   (CALL/? body)
	   (form/simple&side-effect-free? value)
	   (not (form/static? value)))))

;; Note: this only works if no variable free in value is captured
;; at any reference in node.
;; This is currently true by construction, but may not be in the future.

(define (simplify/substitute! node value)
  (for-each (lambda (ref)
	      (simplify/remember*! ref value)
	      (form/rewrite! ref value))
	    (simplify/binding/ordinary-refs node))
  (for-each (lambda (ref)
	      (form/rewrite! ref value))
	    (simplify/binding/dbg-info-refs node))
  (for-each (lambda (ref)
	      (form/rewrite! ref `(CALL ,value ,@(cddr ref))))
	    (simplify/binding/operator-refs node)))

(define (simplify/pseudo-letify rator bindings body)
  (pseudo-letify rator bindings body simplify/remember))

(define (simplify/letify bindings body)
  `(LET ,bindings ,body))

(define (simplify/letrecify bindings body)
  `(LETREC ,bindings ,body))

(define (simplify/open-code? name value unsafe-cyclic-reference?)
  ;; VALUE must be a lambda expression
  (let ((body (lambda/body value)))
    (or (QUOTE/? body)
	(LOOKUP/? body)
	(and *after-cps-conversion?*
	     (CALL/? body)
	     (<= (length (call/cont-and-operands body))
		 (1+ (length (lambda/formals value))))
	     (not (unsafe-cyclic-reference? name))
	     (for-all? (cdr body)
		       (lambda (element)
			 (or (QUOTE/? element)
			     (LOOKUP/? element))))))))

(define (simplify/expr env expr)
  (if (not (pair? expr))
      (illegal expr))
  (case (car expr)
    ((QUOTE)
     (simplify/quote env expr))
    ((LOOKUP)
     (simplify/lookup env expr))
    ((LAMBDA)
     (simplify/lambda env expr))
    ((LET)
     (simplify/let env expr))
    ((DECLARE)
     (simplify/declare env expr))
    ((CALL)
     (simplify/call env expr))
    ((BEGIN)
     (simplify/begin env expr))
    ((IF)
     (simplify/if env expr))
    ((LETREC)
     (simplify/letrec env expr))
    ((SET! UNASSIGNED? OR DELAY
      ACCESS DEFINE IN-PACKAGE THE-ENVIRONMENT)
     (no-longer-legal expr))
    (else
     (illegal expr))))

(define (simplify/expr* env exprs)
  (lmap (lambda (expr)
	  (simplify/expr env expr))
	exprs))

(define (simplify/remember new old)
  (code-rewrite/remember new old))

(define (simplify/remember*! new old)
  (code-rewrite/remember*! new (code-rewrite/original-form old)))

(define (simplify/new-name prefix)
  (new-variable prefix))



(define (simplify/get-dbg-info env expr)
  (cond ((code-rewrite/original-form/previous expr)
         => (lambda (dbg-info)
	      ;; Copy the dbg info, keeping dbg-info-refs in the environment
              ;; which may later be overwritten
              (let* ((block     (new-dbg-form/block dbg-info))
                     (block*    (new-dbg-block/copy-transforming
                                 (lambda (expr)
                                   (simplify/copy-dbg-kmp expr env))
                                 block))
                     (dbg-info* (new-dbg-form/new-block dbg-info block*)))
                dbg-info*)))
        (else #F)))


(define (simplify/copy-dbg-kmp expr env)
  (form/copy-transforming
   (lambda (form copy uninteresting)
     copy
     (cond ((and (LOOKUP/? form)
		 (simplify/lookup*! env (lookup/name form)
				    `(LOOKUP ,(lookup/name form))
				    'DBG-INFO))
	    => (lambda (reference)  reference))
	   (else (uninteresting form))))
   expr))

(define-structure
    (simplify/binding
     (conc-name simplify/binding/)
     (constructor simplify/binding/make (name))
     (print-procedure
      (standard-unparser-method 'SIMPLIFY/BINDING
	(lambda (binding port)
	  (write-char #\space port)
	  (write-string (symbol-name (simplify/binding/name binding)) port)))))

  (name false read-only true)
  (ordinary-refs '() read-only false)
  (operator-refs '() read-only false)
  (dbg-info-refs '() read-only false))

(define-structure
    (simplify/env
     (conc-name simplify/env/)
     (constructor simplify/env/make (parent bindings))
     (print-procedure
      (standard-unparser-method 'SIMPLIFY/ENV
	(lambda (env port)
	  (write-char #\Space port)
	  (write (map simplify/binding/name (simplify/env/bindings env))
		 port)))))

  (bindings '() read-only true)
  (parent #F read-only true)
  ;; FREE-CALLS is used to mark calls to names free in this frame but bound
  ;; in the parent frame.  Used to detect mutual recursion in LETREC.
  (free-calls '() read-only false))

(define (simplify/env/modified-copy old-env new-bindings)
  (let ((result (simplify/env/make (simplify/env/parent old-env)
				   new-bindings)))
    (set-simplify/env/free-calls! result
     (simplify/env/free-calls old-env))
    result))


(define simplify/env/frame-lookup
    (association-procedure (lambda (x y) (eq? x y)) simplify/binding/name))

(define (simplify/lookup*! env name reference kind)
  ;; kind = 'OPERATOR, 'ORDINARY or 'DBG-INFO
  (let frame-loop ((prev #F)
		   (env env))
    (cond ((not env)
	   (if (not (eq? kind 'DBG-INFO))
	       (free-var-error name))
	   reference)
	  ((simplify/env/frame-lookup name (simplify/env/bindings env))
	   => (lambda (binding)
		(case kind
		  ((OPERATOR)
		   (set-simplify/binding/operator-refs!
		    binding
		    (cons reference (simplify/binding/operator-refs binding)))
		   (if prev
		       (set-simplify/env/free-calls!
			prev
			(cons name (simplify/env/free-calls prev)))))
		  ((ORDINARY)
		   (set-simplify/binding/ordinary-refs!
		    binding
		    (cons reference (simplify/binding/ordinary-refs binding))))
		  ((DBG-INFO)
		   (set-simplify/binding/dbg-info-refs!
		    binding
		    (cons reference (simplify/binding/dbg-info-refs binding))))
		  (else
		   (internal-error "simplify/lookup*! bad KIND" kind)))
		reference))
	  (else (frame-loop env (simplify/env/parent env))))))
