#| -*-Scheme-*-

$Header: /Users/cph/tmp/foo/mit-scheme/mit-scheme/v7/src/compiler/machines/vax/rules1.scm,v 4.7 1991/02/15 00:42:13 jinx Exp $
$MC68020-Header: rules1.scm,v 4.34 1991/01/23 21:34:30 jinx Exp $

Copyright (c) 1987, 1989, 1991 Massachusetts Institute of Technology

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

;;;; LAP Generation Rules: Data Transfers.
;;; Note: All fixnum code is in rulfix.scm
;;; package: (compiler lap-syntaxer)

(declare (usual-integrations))

;;;; Register Assignments

;;; All assignments to pseudo registers are required to delete the
;;; dead registers BEFORE performing the assignment.  However, it is
;;; necessary to derive the effective address of the source
;;; expression(s) before deleting the dead registers.  Otherwise any
;;; source expression containing dead registers might refer to aliases
;;; which have been reused.

(define-rule statement
  (ASSIGN (REGISTER (? target)) (REGISTER (? source)))
  (assign-register->register target source))

(define-rule statement
  (ASSIGN (REGISTER (? target)) (OFFSET-ADDRESS (REGISTER (? source)) (? n)))
  (load-displaced-register target source (* 4 n)))

(define-rule statement
  ;; This is an intermediate rule -- not intended to produce code.
  (ASSIGN (REGISTER (? target))
	  (CONS-POINTER (MACHINE-CONSTANT (? type))
			(OFFSET-ADDRESS (REGISTER (? source)) (? n))))
  (load-displaced-register/typed target source type (* 4 n)))

(define-rule statement
  (ASSIGN (REGISTER (? target))
	  (BYTE-OFFSET-ADDRESS (REGISTER (? source)) (? n)))
  (load-displaced-register target source n))

(define-rule statement
  (ASSIGN (REGISTER (? target))
	  (CONS-POINTER (MACHINE-CONSTANT (? type))
			(BYTE-OFFSET-ADDRESS (REGISTER (? source)) (? n))))
  (load-displaced-register/typed target source type n))

(define-rule statement
  (ASSIGN (REGISTER (? target)) (OBJECT->TYPE (REGISTER (? source))))
  (convert-object/register->register target source object->type))

(define-rule statement
  (ASSIGN (REGISTER (? target))
	  (CONS-POINTER (REGISTER (? type)) (REGISTER (? datum))))
  (cond ((register-copy-if-available datum 'GENERAL target)
	 =>
	 (lambda (get-datum-alias)
	   (let* ((type (any-register-reference type))
		  (datum&target (get-datum-alias)))
	     (set-type/ea type datum&target))))
	((register-copy-if-available type 'GENERAL target)
	 =>
	 (lambda (get-type-alias)
	   (let* ((datum (any-register-reference datum))
		  (type&target (get-type-alias)))
	     (cons-pointer/ea type&target datum type&target))))
	(else
	 (let* ((type (any-register-reference type))
		(datum (any-register-reference datum))
		(target (standard-target-reference target)))
	   (cons-pointer/ea type datum target)))))

(define-rule statement
  (ASSIGN (REGISTER (? target))
	  (CONS-POINTER (MACHINE-CONSTANT (? type)) (REGISTER (? datum))))
  (if (zero? type)
      (assign-register->register target datum)
      (with-register-copy-alias! datum 'GENERAL target
	(lambda (alias)
	  (set-type/constant type alias))
	(lambda (datum target)
	  (cons-pointer/constant type datum target)))))

(define-rule statement
  (ASSIGN (REGISTER (? target)) (OBJECT->DATUM (REGISTER (? source))))
  (convert-object/register->register target source object->datum))

(define-rule statement
  (ASSIGN (REGISTER (? target)) (OBJECT->ADDRESS (REGISTER (? source))))
  (convert-object/register->register target source object->address))

;;;; Loading Constants

(define-rule statement
  (ASSIGN (REGISTER (? target)) (CONSTANT (? source)))
  (load-constant source (standard-target-reference target)))

(define-rule statement
  (ASSIGN (REGISTER (? target)) (MACHINE-CONSTANT (? n)))
  (load-immediate n (standard-target-reference target)))

(define-rule statement
  (ASSIGN (REGISTER (? target))
	  (CONS-POINTER (MACHINE-CONSTANT (? type))
			(MACHINE-CONSTANT (? datum))))
  (load-non-pointer type datum (standard-target-reference target)))

(define-rule statement
  (ASSIGN (REGISTER (? target)) (ENTRY:PROCEDURE (? label)))
  (load-pc-relative-address
   target
   (rtl-procedure/external-label (label->object label))))

(define-rule statement
  (ASSIGN (REGISTER (? target)) (ENTRY:CONTINUATION (? label)))
  (load-pc-relative-address target label))

(define-rule statement
  ;; This is an intermediate rule -- not intended to produce code.
  (ASSIGN (REGISTER (? target))
	  (CONS-POINTER (MACHINE-CONSTANT (? type))
			(ENTRY:PROCEDURE (? label))))
  (load-pc-relative-address/typed target
				  type
				  (rtl-procedure/external-label
				   (label->object label))))

(define-rule statement
  ;; This is an intermediate rule -- not intended to produce code.
  (ASSIGN (REGISTER (? target))
	  (CONS-POINTER (MACHINE-CONSTANT (? type))
			(ENTRY:CONTINUATION (? label))))
  (load-pc-relative-address/typed target type label))

(define-rule statement
  (ASSIGN (REGISTER (? target)) (VARIABLE-CACHE (? name)))
  (load-pc-relative target (free-reference-label name)))

(define-rule statement
  (ASSIGN (REGISTER (? target)) (ASSIGNMENT-CACHE (? name)))
  (load-pc-relative target (free-assignment-label name)))

(define-rule statement
  (ASSIGN (REGISTER (? target)) (OBJECT->DATUM (CONSTANT (? constant))))
  (convert-object/constant->register target constant
				     object->datum ct/object->datum))

(define-rule statement
  (ASSIGN (REGISTER (? target)) (OBJECT->ADDRESS (CONSTANT (? constant))))
  (convert-object/constant->register target constant
				     object->address ct/object->address))

;;;; Transfers from Memory

(define-rule statement
  (ASSIGN (REGISTER (? target))
	  (OBJECT->TYPE (OFFSET (REGISTER (? address)) (? offset))))
  (convert-object/offset->register target address offset object->type))

(define-rule statement
  (ASSIGN (REGISTER (? target))
	  (OBJECT->DATUM (OFFSET (REGISTER (? address)) (? offset))))
  (convert-object/offset->register target address offset object->datum))

(define-rule statement
  (ASSIGN (REGISTER (? target))
	  (OBJECT->ADDRESS (OFFSET (REGISTER (? address)) (? offset))))
  (convert-object/offset->register target address offset object->address))

(define-rule statement
  (ASSIGN (REGISTER (? target)) (OFFSET (REGISTER (? address)) (? offset)))
  (let ((source (indirect-reference! address offset)))
    (LAP (MOV L ,source ,(standard-target-reference target)))))

(define-rule statement
  (ASSIGN (REGISTER (? target)) (POST-INCREMENT (REGISTER 14) 1))
  (LAP (MOV L (@R+ 14) ,(standard-target-reference target))))

;;;; Transfers to Memory

(define-rule statement
  (ASSIGN (OFFSET (REGISTER (? a)) (? n))
	  (CONSTANT (? object)))
  (load-constant object (indirect-reference! a n)))

(define-rule statement
  (ASSIGN (OFFSET (REGISTER (? a)) (? n))
	  (CONS-POINTER (MACHINE-CONSTANT (? type))
			(MACHINE-CONSTANT (? datum))))
  (load-non-pointer type datum (indirect-reference! a n)))

(define-rule statement
  (ASSIGN (OFFSET (REGISTER (? a)) (? n)) (REGISTER (? r)))
  (QUALIFIER (register-value-class=word? r))
  (LAP (MOV L
	    ,(any-register-reference r)
	    ,(indirect-reference! a n))))

(define-rule statement
  (ASSIGN (OFFSET (REGISTER (? a)) (? n))
	  (POST-INCREMENT (REGISTER 14) 1))
  (LAP (MOV L (@R+ 14) ,(indirect-reference! a n))))

(define-rule statement
  (ASSIGN (OFFSET (REGISTER (? address)) (? offset))
	  (CONS-POINTER (MACHINE-CONSTANT (? type)) (REGISTER (? datum))))
  (let ((target (indirect-reference! address offset)))
    (cons-pointer/constant type
			   (any-register-reference datum)
			   target)))

(define-rule statement
  (ASSIGN (OFFSET (REGISTER (? address)) (? offset))
	  (CONS-POINTER (MACHINE-CONSTANT (? type))
			(OFFSET-ADDRESS (REGISTER (? source)) (? n))))
  (store-displaced-register/typed address offset type source (* 4 n)))

(define-rule statement
  (ASSIGN (OFFSET (REGISTER (? address)) (? offset))
	  (CONS-POINTER (MACHINE-CONSTANT (? type))
			(BYTE-OFFSET-ADDRESS (REGISTER (? source)) (? n))))
  (store-displaced-register/typed address offset type source n))

;; Common case that can be done cheaply:

(define-rule statement
  (ASSIGN (OFFSET (REGISTER (? address)) (? offset))
	  (BYTE-OFFSET-ADDRESS (OFFSET (REGISTER (? address)) (? offset))
			       (? n)))
  (if (zero? n)
      (LAP)
      (increment/ea (indirect-reference! address offset) n)))

(define-rule statement
  (ASSIGN (OFFSET (REGISTER (? address)) (? offset))
	  (CONS-POINTER (MACHINE-CONSTANT (? type))
			(ENTRY:PROCEDURE (? label))))
  (let ((target (indirect-reference! address offset))
	(label (rtl-procedure/external-label (label->object label))))
    #|
    (LAP (MOVA B (@PCR ,label) ,target)
	 ,@(set-type/constant type target))
    |#
    (LAP (MOVA B (@PCRO ,label ,(make-non-pointer-literal type 0)) ,target))))

(define-rule statement
  (ASSIGN (OFFSET (REGISTER (? a0)) (? n0))
	  (OFFSET (REGISTER (? a1)) (? n1)))
  (if (and (= a0 a1) (= n0 n1))
      (LAP)
      (let ((source (indirect-reference! a1 n1)))
	(LAP (MOV L ,source ,(indirect-reference! a0 n0))))))

;;;; Consing

(define-rule statement
  (ASSIGN (POST-INCREMENT (REGISTER 12) 1) (CONSTANT (? object)))
  (load-constant object (INST-EA (@R+ 12))))

(define-rule statement
  (ASSIGN (POST-INCREMENT (REGISTER 12) 1)
	  (CONS-POINTER (MACHINE-CONSTANT (? type))
			(MACHINE-CONSTANT (? datum))))
  (load-non-pointer type datum (INST-EA (@R+ 12))))

(define-rule statement
  (ASSIGN (POST-INCREMENT (REGISTER 12) 1) (REGISTER (? r)))
  (QUALIFIER (register-value-class=word? r))
  (LAP (MOV L ,(any-register-reference r) (@R+ 12))))

(define-rule statement
  (ASSIGN (POST-INCREMENT (REGISTER 12) 1) (OFFSET (REGISTER (? r)) (? n)))
  (LAP (MOV L ,(indirect-reference! r n) (@R+ 12))))

(define-rule statement
  ;; This pops the top of stack into the heap
  (ASSIGN (POST-INCREMENT (REGISTER 12) 1) (POST-INCREMENT (REGISTER 14) 1))
  (LAP (MOV L (@R+ 14) (@R+ 12))))

;;;; Pushes

(define-rule statement
  (ASSIGN (PRE-INCREMENT (REGISTER 14) -1) (REGISTER (? r)))
  (QUALIFIER (register-value-class=word? r))
  (LAP (PUSHL ,(any-register-reference r))))

(define-rule statement
  (ASSIGN (PRE-INCREMENT (REGISTER 14) -1) (CONSTANT (? object)))
  (LAP (PUSHL ,(constant->ea object))))

(define-rule statement
  (ASSIGN (PRE-INCREMENT (REGISTER 14) -1)
	  (CONS-POINTER (MACHINE-CONSTANT (? type)) (REGISTER (? datum))))
  (LAP (PUSHL ,(any-register-reference datum))
       ,@(set-type/constant type (INST-EA (@R 14)))))

(define-rule statement
  (ASSIGN (PRE-INCREMENT (REGISTER 14) -1)
	  (CONS-POINTER (MACHINE-CONSTANT (? type))
			(MACHINE-CONSTANT (? datum))))
  (LAP (PUSHL ,(non-pointer->ea type datum))))

(define-rule statement
  (ASSIGN (PRE-INCREMENT (REGISTER 14) -1)
	  (CONS-POINTER (MACHINE-CONSTANT (? type))
			(ENTRY:PROCEDURE (? label))))
  (push-pc-relative-address/typed type
				  (rtl-procedure/external-label
				   (label->object label))))

(define-rule statement
  (ASSIGN (PRE-INCREMENT (REGISTER 14) -1)
	  (CONS-POINTER (MACHINE-CONSTANT (? type))
			(ENTRY:CONTINUATION (? label))))
  (push-pc-relative-address/typed type label))

(define-rule statement
  (ASSIGN (PRE-INCREMENT (REGISTER 14) -1)
	  (CONS-POINTER (MACHINE-CONSTANT (? type))
			(OFFSET-ADDRESS (REGISTER (? r)) (? n))))
  (push-displaced-register/typed type r (* 4 n)))

(define-rule statement
  (ASSIGN (PRE-INCREMENT (REGISTER 14) -1)
	  (CONS-POINTER (MACHINE-CONSTANT (? type))
			(BYTE-OFFSET-ADDRESS (REGISTER (? r)) (? n))))
  (push-displaced-register/typed type r n))

(define-rule statement
  (ASSIGN (PRE-INCREMENT (REGISTER 14) -1) (OFFSET (REGISTER (? r)) (? n)))
  (LAP (PUSHL ,(indirect-reference! r n))))

;;;; CHAR->ASCII/BYTE-OFFSET

(define-rule statement
  (ASSIGN (REGISTER (? target))
	  (CHAR->ASCII (OFFSET (REGISTER (? address)) (? offset))))
  (load-char-into-register 0
			   (indirect-char/ascii-reference! address offset)
			   target))

(define-rule statement
  (ASSIGN (REGISTER (? target))
	  (CHAR->ASCII (REGISTER (? source))))
  (load-char-into-register 0
			   (reference-alias-register! source 'GENERAL)
			   target))

(define-rule statement
  (ASSIGN (REGISTER (? target))
	  (BYTE-OFFSET (REGISTER (? address)) (? offset)))
  (load-char-into-register 0
			   (indirect-byte-reference! address offset)
			   target))

(define-rule statement
  (ASSIGN (REGISTER (? target))
	  (CONS-POINTER (MACHINE-CONSTANT (? type))
			(BYTE-OFFSET (REGISTER (? address)) (? offset))))
  (load-char-into-register type
			   (indirect-byte-reference! address offset)
			   target))

(define-rule statement
  (ASSIGN (BYTE-OFFSET (REGISTER (? address)) (? offset))
	  (CHAR->ASCII (CONSTANT (? character))))
  (LAP (MOV B
	    (& ,(char->signed-8-bit-immediate character))
	    ,(indirect-byte-reference! address offset))))

(define-rule statement
  (ASSIGN (BYTE-OFFSET (REGISTER (? address)) (? offset))
	  (REGISTER (? source)))
  (let ((source (coerce->any/byte-reference source)))
    (let ((target (indirect-byte-reference! address offset)))
      (LAP (MOV B ,source ,target)))))

(define-rule statement
  (ASSIGN (BYTE-OFFSET (REGISTER (? address)) (? offset))
	  (CHAR->ASCII (REGISTER (? source))))
  (let ((source (coerce->any/byte-reference source)))
    (let ((target (indirect-byte-reference! address offset)))
      (LAP (MOV B ,source ,target)))))

(define-rule statement
  (ASSIGN (BYTE-OFFSET (REGISTER (? target)) (? target-offset))
	  (CHAR->ASCII (OFFSET (REGISTER (? source)) (? source-offset))))
  (let ((source (indirect-char/ascii-reference! source source-offset)))
    (LAP (MOV B ,source ,(indirect-byte-reference! target target-offset)))))

;;;; Utilities specific to rules1 (others in lapgen)

(define (load-displaced-register target source n)
  (if (zero? n)
      (assign-register->register target source)
      (with-register-copy-alias! source 'GENERAL target
	(lambda (reusable-alias)
	  (increment/ea reusable-alias n))
	(lambda (source target)
	  (add-constant/ea source n target)))))

(define (load-displaced-register/typed target source type n)
  (if (zero? type)
      (load-displaced-register target source n)
      (let ((unsigned-offset (+ (make-non-pointer-literal type 0) n)))
	(with-register-copy-alias! source 'GENERAL target
	  (lambda (reusable-alias)
	    (LAP (ADD L (&U ,unsigned-offset) ,reusable-alias)))
	  (lambda (source target)
	    (LAP (ADD L (&U ,unsigned-offset) ,source ,target)))))))

(define (store-displaced-register/typed address offset type source n)
  (let* ((source (any-register-reference source))
	 (target (indirect-reference! address offset)))
    (if (zero? type)
	(add-constant/ea source n target)
	(LAP (ADD L (&U ,(+ (make-non-pointer-literal type 0) n))
		  ,source ,target)))))

(define (push-displaced-register/typed type r n)
  (if (zero? type)
      (LAP (PUSHA B ,(indirect-byte-reference! r n)))
      #|
      (LAP (PUSHA B ,(indirect-byte-reference! r n))
	   (set-type/constant type (INST-EA (@R 14))))
      |#
      (let ((reg (allocate-indirection-register! r)))
	(LAP (PUSHA B (@RO UL ,reg ,(+ (make-non-pointer-literal type 0)
				       n)))))))

(define (assign-register->register target source)
  (move-to-alias-register! source (register-type target) target)
  (LAP))

(define (load-pc-relative target label)
  (LAP (MOV L (@PCR ,label) ,(standard-target-reference target))))

(define (load-pc-relative-address target label)
  (LAP (MOVA B (@PCR ,label) ,(standard-target-reference target))))

(define (load-pc-relative-address/typed target type label)
  (let ((target (standard-target-reference target)))
    #|
    (LAP (MOVA B (@PCR ,label) ,target)
	 ,@(set-type/constant type target))
    |#
    (LAP (MOVA B (@PCRO ,label ,(make-non-pointer-literal type 0)) ,target))))

(define (push-pc-relative-address/typed type label)
  #|
  (LAP (PUSHA B (@PCR ,label))
       ,@(set-type/constant type (INST-EA (@R 14))))
  |#
  (LAP (PUSHA B (@PCRO ,label ,(make-non-pointer-literal type 0)))))

(define (load-char-into-register type source target)
  (let ((target (standard-target-reference target)))
    (LAP ,@(load-non-pointer type 0 target)
	 (MOV B ,source ,target))))