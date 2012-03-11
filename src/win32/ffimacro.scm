#| -*-Scheme-*-

Copyright (C) 1986, 1987, 1988, 1989, 1990, 1991, 1992, 1993, 1994,
    1995, 1996, 1997, 1998, 1999, 2000, 2001, 2002, 2003, 2004, 2005,
    2006, 2007, 2008, 2009, 2010, 2011, 2012 Massachusetts Institute
    of Technology

This file is part of MIT/GNU Scheme.

MIT/GNU Scheme is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at
your option) any later version.

MIT/GNU Scheme is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with MIT/GNU Scheme; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301,
USA.

|#

(declare (usual-integrations))

#|
WINDOWS PROCEDURE TYPE SYSTEM

Each type TYPE has 4 procedures associated with it.  The association is by
the following naming scheme:

  (TYPE:CHECK x)    a predicate.  Returns #t if its argument is acceptable
  (TYPE:CONVERT x)  converts an argument into a form suitable for the foreign
                    function.
  (TYPE:RETURN-CONVERT x)  converts from the C retrun values to a scheme object
  (TYPE:REVERT x xcvt) This is for mirriring changes to variables passed by
                       reference.  X is the original argument, XCVT is the
                       result of (TYPE:CONVERT X) which has already been passed
                       to the foreign function.  The idea is that TYPE:REVERT
                       updates X to reflect the changes in XCVT.

Additionally, there is another derived procedure, (TYPE:CHECK&CONVERT x)
which checks the argument and then does conversion.


DEFINE-WINDOWS-TYPE and DEFINE-SIMILAR-WINDOWS-TYPE macros

(DEFINE-WINDOWS-TYPE <name> <check> <convert> <return> <revert>)

This defines <name> to be a type according to the above scheme.  <name> is a
symbol.  The other components are either functions, or #f for the default
operation (which is do nothing).

Thus we could define the type char as follows:

  (define-windows-type char
     char?          ; <check>
     char->integer  ;
     integer->char  ;
     #f)            ; no reversion


(DEFINE-SIMILAR-WINDOWS-TYPE <name> <model>
        #!optional  <check> <convert> <return> <revert>)

This defines a type as above, but the defaults are taken from the type <model>
rather than defaulting to null operations.


WINDOWS-PROCEDURE macro

(WINDOWS-PROCEDURE (foo (argname type) ...)  module entry-name)
(WINDOWS-PROCEDURE (foo (argname type) ...)  module entry-name WITH-REVERSIONS)
(WINDOWS-PROCEDURE (foo (argname type) ...)  module entry-name EXPAND)
(WINDOWS-PROCEDURE (foo (argname type) ...)  module entry-name <CODE>)

The first form generates a slower but more compact version, based on a generic
n-place higher order procedure parameterized with the check&convert functions.
No reversion code is inserted.  If any of the argument types has a reversion
procedure then the first form should not be used.

The other versions generate faster code by using macro expansion to
insert the type handling functions.  As the type handling functions
generated by DEFINE-WINDOWS-TYPE are declared integrable and are often
simple or trivial, this removes the cost of a general function call to
convert each parameter.  EXPAND and WITH-REVERSIONS have the same
effect, but allow the user to `document' the reason for using the
expanded form.

The final form also generates an expanded form, and inserts <CODE>
after the type checking but before the type conversion.  This allows
extra consistency checks to be placed, especially checks that several
arguments are mutualy consistent (e.g. an index into a buffer indexes
to inside a string that is being used as the buffer).
|#

(define-syntax windows-procedure
  (sc-macro-transformer
   (lambda (form environment)
     (let ((args (cadr form))
	   (return-type (caddr form))
	   (module (close-syntax (cadddr form) environment))
	   (entry-name (close-syntax (car (cddddr form)) environment))
	   (additional-specifications (cdr (cddddr form))))
       (if additional-specifications
	   ;; expanded version:
	   (let* ((procedure-name (car args))
		  (arg-names (map car (cdr args)))
		  (arg-types (map cadr (cdr args)))
		  (cvt-names
		   (map (lambda (sym)
			  (intern
			   (string-append "[converted "
					  (symbol-name sym)
					  "]")))
			arg-names)))
	     `((ACCESS PARAMETERIZE-WITH-MODULE-ENTRY
		       SYSTEM-GLOBAL-ENVIRONMENT)
	       (LAMBDA (,ffi-module-entry-variable)
		 (NAMED-LAMBDA (,procedure-name ,@arg-names)
		   ,@(map (lambda (type arg)
			    `(IF (NOT (,(type->checker type environment) ,arg))
				 (WINDOWS-PROCEDURE-ARGUMENT-TYPE-CHECK-ERROR
				  ',type
				  ,arg)))
			  arg-types
			  arg-names)
		   ,@(if (and (pair? additional-specifications)
			      (symbol? (car additional-specifications)))
			 (cdr additional-specifications)
			 additional-specifications)
		   (LET ,(map (lambda (cvt-name arg-type arg-name)
				`(,cvt-name
				  (,(type->converter arg-type environment)
				   ,arg-name)))
			      cvt-names
			      arg-types
			      arg-names)
		       (LET ((,ffi-result-variable
			      (%CALL-FOREIGN-FUNCTION
			       (MODULE-ENTRY/MACHINE-ADDRESS
				,ffi-module-entry-variable)
			       ,@cvt-names)))
			 ,@(map (lambda (type arg-name cvt-name)
				  `(,(type->reverter type environment)
				    ,arg-name
				    ,cvt-name))
				arg-types
				arg-names
				cvt-names)
			 (,(type->return-converter return-type environment)
			  ,ffi-result-variable)))))
	       ,module
	       ,entry-name))
	   ;; closure version:
	   (let ((arg-types (map cadr (cdr args))))
	     `(MAKE-WINDOWS-PROCEDURE
	       ,module
	       ,entry-name
	       ,(type->return-converter return-type environment)
	       ,@(map (lambda (name)
			(type->check&converter name environment))
		      arg-types))))))))

(define-syntax define-windows-type
  (sc-macro-transformer
   (lambda (form environment)
     (let ((name (list-ref form 1))
	   (check
	    (or (and (> (length form) 2)
		     (list-ref form 2))
		'(LAMBDA (X) X #T)))
	   (convert
	    (or (and (> (length form) 3)
		     (list-ref form 3))
		'(LAMBDA (X) X)))
	   (return
	    (or (and (> (length form) 4)
		     (list-ref form 4))
		'(LAMBDA (X) X)))
	   (revert
	    (or (and (> (length form) 5)
		     (list-ref form 5))
		'(LAMBDA (X Y) X Y UNSPECIFIC))))
       `(BEGIN 
	  (DEFINE-INTEGRABLE (,(type->checker name) X)
	    (,check X))
	  (DEFINE-INTEGRABLE (,(type->converter name) X)
	    (,convert X))
	  (DEFINE-INTEGRABLE (,(type->check&converter name) X)
	    (IF (,(type->checker name environment) X)
		(,(type->converter name environment) X)
		(WINDOWS-PROCEDURE-ARGUMENT-TYPE-CHECK-ERROR ',name X)))
	  (DEFINE-INTEGRABLE (,(type->return-converter name) X)
	    (,return X))
	  (DEFINE-INTEGRABLE (,(type->reverter name) X Y)
	    (,revert X Y)))))))

(define-syntax define-similar-windows-type
  (sc-macro-transformer
   (lambda (form environment)
     (let ((name (list-ref form 1))
	   (model (list-ref form 2)))
       (let ((check
	      (or (and (> (length form) 3)
		       (list-ref form 3))
		  (type->checker model environment)))
	     (convert
	      (or (and (> (length form) 4)
		       (list-ref form 4))
		  (type->converter model environment)))
	     (return
	      (or (and (> (length form) 5)
		       (list-ref form 5))
		  (type->return-converter model environment)))
	     (revert
	      (or (and (> (length form) 6)
		       (list-ref form 6))
		  (type->reverter model environment))))
	 `(BEGIN
	    (DEFINE-INTEGRABLE (,(type->checker name) X)
	      (,check X))
	    (DEFINE-INTEGRABLE (,(type->converter name) X)
	      (,convert X))
	    (DEFINE-INTEGRABLE (,(type->check&converter name) X)
	      (IF (,(type->checker name environment) X)
		  (,(type->converter name environment) X)
		  (WINDOWS-PROCEDURE-ARGUMENT-TYPE-CHECK-ERROR ',name X)))
	    (DEFINE-INTEGRABLE (,(type->return-converter name) X)
	      (,return X))
	    (DEFINE-INTEGRABLE (,(type->reverter name) X Y)
	      (,revert X Y))))))))

(define ((make-type-namer suffix) type #!optional environment)
  (let ((name (symbol-append type suffix)))
    (if (default-object? environment)
	name
	(close-syntax name environment))))

(define type->checker (make-type-namer ':CHECK))
(define type->converter (make-type-namer ':CONVERT))
(define type->check&converter (make-type-namer ':CHECK&CONVERT))
(define type->return-converter (make-type-namer ':RETURN-CONVERT))
(define type->reverter (make-type-namer ':REVERT))

(define ffi-module-entry-variable
  (string->symbol "[ffi entry]"))
(define ffi-result-variable
  (string->symbol "[ffi result]"))