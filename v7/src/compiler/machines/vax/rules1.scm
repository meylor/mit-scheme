#| -*-Scheme-*-

$Header: /Users/cph/tmp/foo/mit-scheme/mit-scheme/v7/src/compiler/machines/vax/rules1.scm,v 4.4 1988/03/21 21:46:31 bal Exp $

Copyright (c) 1987 Massachusetts Institute of Technology

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

;;;; VAX LAP Generation Rules: Data Transfers
;;;  Matches MC68020 version 4.2

(declare (usual-integrations))

;;;; Transfers to Registers

(define-rule statement
  (ASSIGN (REGISTER 14) (OFFSET-ADDRESS (REGISTER (? source)) (? offset)))
  (QUALIFIER (pseudo-register? source))
  (LAP (MOVA L ,(indirect-reference! source offset) (R 14))))

(define-rule statement
  (ASSIGN (REGISTER 10) (REGISTER 14))
  (LAP (MOV L (R 14) (R 10))))

(define-rule statement
  (ASSIGN (REGISTER 10) (OFFSET-ADDRESS (REGISTER 14) (? offset)))
  (let ((offset1 (* 4 offset)))
    (LAP (MOVA L (@RO ,(offset-type offset1) 14 ,offset1) (R 10)))))

(define-rule statement
  (ASSIGN (REGISTER 10) (OFFSET-ADDRESS (REGISTER (? source)) (? offset)))
  (QUALIFIER (pseudo-register? source))
  (LAP (MOVA L ,(indirect-reference! source offset) (R 10))))
  
(define-rule statement
  (ASSIGN (REGISTER 10) (OBJECT->ADDRESS (REGISTER (? source))))
  (QUALIFIER (pseudo-register? source))
  (if (and (dead-register? source)
	   (register-has-alias? source 'GENERAL))
      (let ((source (register-reference (register-alias source 'GENERAL))))
	(LAP (BIC L ,mask-reference ,source (R 10))))
      (let ((temp (reference-temporary-register! 'GENERAL)))
	(LAP (MOV L ,(coerce->any source) ,temp)
	     (BIC L ,mask-reference ,temp (R 10))))))

;;; All assignments to pseudo registers are required to delete the
;;; dead registers BEFORE performing the assignment.  This is because
;;; the register being assigned may be PSEUDO-REGISTER=? to one of the
;;; dead registers, and thus would be flushed if the deletions
;;; happened after the assignment.

(define-rule statement
  (ASSIGN (REGISTER 14) (OFFSET-ADDRESS (REGISTER 14) (? n)))
  (increment-rnl 14 n))

(define-rule statement
  (ASSIGN (REGISTER (? target)) (OFFSET-ADDRESS (REGISTER 14) (? n)))
  (QUALIFIER (pseudo-register? target))
  ;; An alias is used here as eager register caching.  It wins often.
  (let ((offset (* 4 n)))
    (LAP
     (MOVA L (@RO ,(offset-type offset) 14 ,offset)
	     ,(reference-assignment-alias! target 'GENERAL)))))

(define-rule statement
  (ASSIGN (REGISTER 14) (REGISTER (? source)))
  (LAP (MOV L ,(coerce->any source) (R 14))))

(define-rule statement
  (ASSIGN (REGISTER (? target)) (CONSTANT (? source)))
  (QUALIFIER (pseudo-register? target))
  (LAP ,(load-constant source (coerce->any target))))

(define-rule statement
  (ASSIGN (REGISTER (? target)) (VARIABLE-CACHE (? name)))
  (QUALIFIER (pseudo-register? target))
  (LAP (MOV L
	    (@PCR ,(free-reference-label name))
	    ,(reference-assignment-alias! target 'GENERAL))))

(define-rule statement
  (ASSIGN (REGISTER (? target)) (ASSIGNMENT-CACHE (? name)))
  (QUALIFIER (pseudo-register? target))
  (LAP (MOV L
	    (@PCR ,(free-assignment-label name))
	    ,(reference-assignment-alias! target 'GENERAL))))

(define-rule statement
  (ASSIGN (REGISTER (? target)) (REGISTER (? source)))
  (QUALIFIER (pseudo-register? target))
  (move-to-alias-register! source 'GENERAL target)
  (LAP))

(define-rule statement
  (ASSIGN (REGISTER (? target)) (OBJECT->ADDRESS (REGISTER (? source))))
  (QUALIFIER (pseudo-register? target))
  (with-register-copy-alias! source 'GENERAL target
   (lambda (target)
     (LAP (BIC L ,mask-reference ,target)))
   (lambda (source target)
     (LAP (BIC L ,mask-reference ,source ,target)))))

(define-rule statement
  (ASSIGN (REGISTER (? target)) (OBJECT->TYPE (REGISTER (? source))))
  (QUALIFIER (pseudo-register? target))
  (with-register-copy-alias! source 'GENERAL target
   (lambda (target)
     (LAP (ROTL (S 8) ,target ,target)))
   (lambda (source target)
     (LAP (ROTL (S 8) ,source ,target)))))

(define-rule statement
  (ASSIGN (REGISTER (? target)) (OFFSET (REGISTER (? address)) (? offset)))
  (QUALIFIER (pseudo-register? target))
  (let ((source (indirect-reference! address offset)))
    (delete-dead-registers!)
    (LAP (MOV L
	      ,source
	      ,(register-reference
		(allocate-alias-register! target 'GENERAL))))))

(define-rule statement
  (ASSIGN (REGISTER (? target)) (POST-INCREMENT (REGISTER 14) 1))
  (QUALIFIER (pseudo-register? target))
  (delete-dead-registers!)
  (LAP (MOV L
	    (@R+ 14)
	    ,(register-reference
	      (allocate-alias-register! target 'GENERAL)))))

(define-rule statement
  (ASSIGN (REGISTER (? target))
	  (CONS-POINTER (CONSTANT (? type)) (REGISTER (? datum))))
  (QUALIFIER (pseudo-register? target))
  (let ((target* (coerce->any target))
	(datum (coerce->any datum)))
    (delete-dead-registers!)
    (let ((can-bump? (bump-type target*)))
      (if (not can-bump?)
	  (LAP (MOV L ,datum ,reg:temp)
	       (MOV B ,(immediate-type type) ,reg:temp-type)
	       (MOV L ,reg:temp ,target*))
	  (LAP (MOV L ,datum ,target*)
	       (MOV B ,(immediate-type type) ,can-bump?))))))

;;;; Transfers to Memory

(define-rule statement
  (ASSIGN (OFFSET (REGISTER (? a)) (? n))
	  (CONSTANT (? object)))
  (LAP ,(load-constant object (indirect-reference! a n))))

(define-rule statement
  (ASSIGN (OFFSET (REGISTER (? a)) (? n))
	  (UNASSIGNED))
  (LAP ,(load-non-pointer (ucode-type unassigned) 0
			  (indirect-reference! a n))))

(define-rule statement
  (ASSIGN (OFFSET (REGISTER (? a)) (? n))
	  (REGISTER (? r)))
  (LAP (MOV L
	    ,(coerce->any r)
	    ,(indirect-reference! a n))))

(define-rule statement
  (ASSIGN (OFFSET (REGISTER (? a)) (? n))
	  (POST-INCREMENT (REGISTER 14) 1))
  (LAP (MOV L
	    (@R+ 14)
	    ,(indirect-reference! a n))))

(define-rule statement
  (ASSIGN (OFFSET (REGISTER (? a)) (? n))
	  (CONS-POINTER (CONSTANT (? type)) (REGISTER (? r))))
  (let ((target (indirect-reference! a n)))
    (LAP (MOV L ,(coerce->any r) ,target)
	 (MOV B ,(immediate-type type) ,(bump-type target)))))

(define-rule statement
  (ASSIGN (OFFSET (REGISTER (? r0)) (? n0))
	  (OFFSET (REGISTER (? r1)) (? n1)))
  (let ((source (indirect-reference! r1 n1)))
    (LAP (MOV L
	      ,source
	      ,(indirect-reference! r0 n0)))))

;;;; Consing

(define-rule statement
  (ASSIGN (POST-INCREMENT (REGISTER 12) 1) (CONSTANT (? object)))
  (LAP ,(load-constant object (INST-EA (@R+ 12)))))

(define-rule statement
  (ASSIGN (POST-INCREMENT (REGISTER 12) 1)
	  (CONS-POINTER (CONSTANT (? type)) (CONSTANT (? datum))))
  (LAP ,(load-non-pointer type datum (INST-EA (@R+ 12)))))

(define-rule statement
  (ASSIGN (POST-INCREMENT (REGISTER 12) 1) (UNASSIGNED))
  (LAP ,(load-non-pointer (ucode-type unassigned) 0 (INST-EA (@R+ 12)))))

(define-rule statement
  (ASSIGN (POST-INCREMENT (REGISTER 12) 1) (REGISTER (? r)))
  (LAP (MOV L ,(coerce->any r) (@R+ 12))))

(define-rule statement
  (ASSIGN (POST-INCREMENT (REGISTER 12) 1) (OFFSET (REGISTER (? r)) (? n)))
  (LAP (MOV L ,(indirect-reference! r n) (@R+ 12))))

(define-rule statement
  (ASSIGN (POST-INCREMENT (REGISTER 12) 1) (ENTRY:PROCEDURE (? label)))
  (LAP (MOVA B (@PCR ,(rtl-procedure/external-label (label->object label)))
	     (@R+ 12))
       (MOV B ,(immediate-type (ucode-type compiled-expression))
	    (@RO B 12 -1))))

;; This pops the top of stack into the heap

(define-rule statement
  (ASSIGN (POST-INCREMENT (REGISTER 12) 1) (POST-INCREMENT (REGISTER 14) 1))
  (LAP (MOV L (@R+ 14) (@R+ 12))))


;;;; Pushes

(define-rule statement
  (ASSIGN (PRE-INCREMENT (REGISTER 14) -1) (CONSTANT (? object)))
  (LAP ,(push-constant object)))

(define-rule statement
  (ASSIGN (PRE-INCREMENT (REGISTER 14) -1) (UNASSIGNED))
  (LAP ,(push-non-pointer (ucode-type unassigned) 0)))

(define-rule statement
  (ASSIGN (PRE-INCREMENT (REGISTER 14) -1) (REGISTER (? r)))
  (LAP (PUSHL ,(coerce->any r))))

(define-rule statement
  (ASSIGN (PRE-INCREMENT (REGISTER 14) -1)
	  (CONS-POINTER (CONSTANT (? type)) (REGISTER (? r))))
  (LAP (PUSHL ,(coerce->any r))
       (MOV B ,(immediate-type type) (@RO B 14 3))))

(define-rule statement
  (ASSIGN (PRE-INCREMENT (REGISTER 14) -1) (OFFSET (REGISTER (? r)) (? n)))
  (LAP (PUSHL ,(indirect-reference! r n))))

(define-rule statement
  (ASSIGN (PRE-INCREMENT (REGISTER 14) -1) (ENTRY:CONTINUATION (? label)))
  (LAP (PUSHA B (@PCR ,label))
       (MOV B ,(immediate-type (ucode-type compiler-return-address))
	    (@RO B 14 3))))
