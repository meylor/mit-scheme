#| -*-Scheme-*-

$Header: /Users/cph/tmp/foo/mit-scheme/mit-scheme/v7/src/runtime/histry.scm,v 14.4 1991/08/06 22:12:23 arthur Exp $

Copyright (c) 1988, 1989, 1990 Massachusetts Institute of Technology

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

;;;; History Manipulation
;;; package: (runtime history)

(declare (usual-integrations))

;;; Vertebrae

(define-integrable (make-vertebra rib deeper shallower)
  (history:unmark (hunk3-cons rib deeper shallower)))

(define-integrable vertebra-rib system-hunk3-cxr0)
(define-integrable deeper-vertebra system-hunk3-cxr1)
(define-integrable shallower-vertebra system-hunk3-cxr2)
(define-integrable set-vertebra-rib! system-hunk3-set-cxr0!)
(define-integrable set-deeper-vertebra! system-hunk3-set-cxr1!)
(define-integrable set-shallower-vertebra! system-hunk3-set-cxr2!)

(define-integrable (marked-vertebra? vertebra)
  (history:marked? (system-hunk3-cxr1 vertebra)))

(define (mark-vertebra! vertebra)
  (system-hunk3-set-cxr1! vertebra
			  (history:mark (system-hunk3-cxr1 vertebra))))

(define (unmark-vertebra! vertebra)
  (system-hunk3-set-cxr1! vertebra
			  (history:unmark (system-hunk3-cxr1 vertebra))))

(define-integrable (same-vertebra? x y)
  (= (object-datum x) (object-datum y)))

(define (link-vertebrae previous next)
  (set-deeper-vertebra! previous next)
  (set-shallower-vertebra! next previous))

;;; Reductions

(define-integrable (make-reduction expression environment next)
  (history:unmark (hunk3-cons expression environment next)))

(define-integrable reduction-expression system-hunk3-cxr0)
(define-integrable reduction-environment system-hunk3-cxr1)
(define-integrable next-reduction system-hunk3-cxr2)
(define-integrable set-reduction-expression! system-hunk3-set-cxr0!)
(define-integrable set-reduction-environment! system-hunk3-set-cxr1!)
(define-integrable set-next-reduction! system-hunk3-set-cxr2!)

(define-integrable (marked-reduction? reduction)
  (history:marked? (system-hunk3-cxr2 reduction)))

(define (mark-reduction! reduction)
  (system-hunk3-set-cxr2! reduction
			  (history:mark (system-hunk3-cxr2 reduction))))

(define (unmark-reduction! reduction)
  (system-hunk3-set-cxr2! reduction
			  (history:unmark (system-hunk3-cxr2 reduction))))

(define-integrable (same-reduction? x y)
  (= (object-datum x) (object-datum y)))

;;; Marks

(define-integrable (history:unmark object)
  (object-new-type (ucode-type unmarked-history) object))

(define-integrable (history:mark object)
  (object-new-type (ucode-type marked-history) object))

(define-integrable (history:marked? object)
  (object-type? (ucode-type marked-history) object))

;;;; History Initialization

(define (create-history depth width)
  (let ((new-vertebra
	 (lambda ()
	   (let ((head (make-reduction false false '())))
	     (set-next-reduction!
	      head
	      (let reduction-loop ((n (-1+ width)))
		(if (zero? n)
		    head
		    (make-reduction false false (reduction-loop (-1+ n))))))
	     (make-vertebra head '() '())))))
    (if (not (and (exact-integer? depth) (positive? depth)))
	(error "CREATE-HISTORY: invalid depth" depth))
    (if (not (and (exact-integer? width) (positive? width)))
	(error "CREATE-HISTORY: invalid width" width))
    (let ((head (new-vertebra)))
      (let subproblem-loop ((n (-1+ depth)) (previous head))
	(if (zero? n)
	    (link-vertebrae previous head)
	    (let ((next (new-vertebra)))
	      (link-vertebrae previous next)
	      (subproblem-loop (-1+ n) next))))
      head)))

;;; The PUSH-HISTORY! accounts for the pop which happens after
;;; SET-CURRENT-HISTORY! is run.

(define (with-new-history thunk)
  (with-history-disabled
    (lambda ()
      ((ucode-primitive set-current-history!)
       (let ((history
	      (push-history! (create-history max-subproblems
					     max-reductions))))
	 (if (zero? max-subproblems)

	     ;; In this case, we want the history to appear empty,
	     ;; so when it pops up, there is nothing in it.
	     history

	     ;; Otherwise, record a dummy reduction, which will appear
	     ;; in the history.
	     (begin (record-evaluation-in-history! history
						   false
						   system-global-environment)
		    (push-history! history)))))
      (thunk))))

(define max-subproblems 10)
(define max-reductions 5)

;;;; Primitive History Operations
;;;  These operations mimic the actions of the microcode.
;;;  The history motion operations all return the new history.

(define (record-evaluation-in-history! history expression environment)
  (let ((current-reduction (vertebra-rib history)))
    (set-reduction-expression! current-reduction expression)
    (set-reduction-environment! current-reduction environment)))

(define (set-history-to-next-reduction! history)
  (let ((next-reduction (next-reduction (vertebra-rib history))))
    (set-vertebra-rib! history next-reduction)
    (unmark-reduction! next-reduction)
    history))

(define (push-history! history)
  (let ((deeper-vertebra (deeper-vertebra history)))
    (mark-vertebra! deeper-vertebra)
    (mark-reduction! (vertebra-rib deeper-vertebra))
    deeper-vertebra))

(define (pop-history! history)
  (unmark-vertebra! history)
  (shallower-vertebra history))

;;;; Side-Effectless Examiners

(define (history-transform history)
  (let loop ((current history))
    (cons current
	  (if (marked-vertebra? current)
	      (cons (delay (unfold-and-reverse-rib (vertebra-rib current)))
		    (delay (let ((next (shallower-vertebra current)))
			     (if (same-vertebra? next history)
				 the-empty-history
				 (loop next)))))
	      '()))))

(define the-empty-history)

(define (unfold-and-reverse-rib rib)
  (let loop ((current (next-reduction rib)) (output 'WRAP-AROUND))
    (let ((step
	   (let ((tail
		  (if (marked-reduction? current)
		      '()
		      output)))
	     (if (dummy-compiler-reduction? current)
		 tail
		 (cons (list (reduction-expression current)
			     (reduction-environment current))
		       tail)))))
      (if (same-reduction? current rib)
	  step
	  (loop (next-reduction current) step)))))

(define (dummy-compiler-reduction? reduction)
  (and (false? (reduction-expression reduction))
       (eq? (ucode-return-address pop-from-compiled-code)
	    (reduction-environment reduction))))

(define (history-superproblem history)
  (if (null? (cdr history))
      history
      (force (cddr history))))

(define (history-reductions history)
  (if (null? (cdr history))
      '()
      (force (cadr history))))

(define-integrable (history-untransform history)
  (car history))

(define (initialize-package!)
  (set! the-empty-history
	(cons (vector-ref (get-fixed-objects-vector)
			  (fixed-objects-vector-slot 'DUMMY-HISTORY))
	      '()))
  unspecific)