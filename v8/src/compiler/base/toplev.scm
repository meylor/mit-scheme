#| -*-Scheme-*-

$Id: toplev.scm,v 1.3 1994/11/23 20:03:26 gjr Exp $

Copyright (c) 1988-1994 Massachusetts Institute of Technology

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

;;;; Compiler Top Level
;;; package: (compiler top-level)

(declare (usual-integrations))

;;;; Usual Entry Point: File Compilation

(define (make-cf compile-bin-file)
  (lambda (input #!optional output)
    (let ((kernel
	   (lambda (source-file)
	     (with-values
		 (lambda () (sf/pathname-defaulting source-file false false))
	       (lambda (source-pathname bin-pathname spec-pathname)
		 ;; Maybe this should be done only if scode-file
		 ;; does not exist or is older than source-file.
		 (sf source-pathname bin-pathname spec-pathname)
		 (if (default-object? output)
		     (compile-bin-file bin-pathname)
		     (compile-bin-file bin-pathname output)))))))
      (if (pair? input)
	  (for-each kernel input)
	  (kernel input)))))

(define (make-cbf compile-bin-file)
  (lambda (input . rest)
    (apply compile-bin-file input rest)))

(define *input-filename-for-temporary-info-info*)

(define (make-compile-bin-file compile-scode/internal)
  (lambda (input-string #!optional output-string)
    (let ((input-default
	   (make-pathname false false false false "bin" 'NEWEST))
	  (output-default
	   (if compiler:cross-compiling?
	       (make-pathname false false false false "moc" false)
	       #F))
	  (inf-file-type (if compiler:cross-compiling? "fni" "inf")))
      (perhaps-issue-compatibility-warning)
      (compiler-pathnames
       input-string
       (if compiler:cross-compiling?
	   (if (not (default-object? output-string))
	       output-string
	       (merge-pathnames output-default
				(merge-pathnames input-string input-default)))
	   (and (not (default-object? output-string)) output-string))
       (make-pathname false false false false "bin" 'NEWEST)
       (lambda (input-pathname output-pathname)
	 (fluid-let ((*input-filename-for-temporary-info-info*
		      (->namestring (->truename input-pathname))))
	   (maybe-open-file
	    compiler:generate-kmp-files?
	    (pathname-new-type output-pathname "kmp")
	    (lambda (kmp-output-port)
	      (maybe-open-file
	       compiler:generate-rtl-files?
	       (pathname-new-type output-pathname "rtl")
	       (lambda (rtl-output-port)
		 (maybe-open-file
		  compiler:generate-lap-files?
		  (pathname-new-type output-pathname "lap")
		  (lambda (lap-output-port)
		    (compile-scode/internal
		     (compiler-fasload input-pathname)
		     (pathname-new-type output-pathname inf-file-type)
		     kmp-output-port
		     rtl-output-port
		     lap-output-port))))))))))
      unspecific)))

(define (maybe-open-file open? pathname receiver)
  (if open?
      (call-with-output-file pathname receiver)
      (receiver false)))

(define (make-compile-expression compile-scode)
  (perhaps-issue-compatibility-warning)
  (lambda (expression #!optional declarations)
    (let ((declarations (if (default-object? declarations)
			    '((usual-integrations))
			    declarations)))
      (compile-scode (syntax&integrate expression declarations)
		     'KEEP))))

(define (make-compile-procedure compile-scode)
  (lambda (procedure #!optional keep-debugging-info?)
    (perhaps-issue-compatibility-warning)
    (compiler-output->procedure
     (compile-scode
      (procedure-lambda procedure)
      (and (or (default-object? keep-debugging-info?)
	       keep-debugging-info?)
	   'KEEP))
     (procedure-environment procedure))))

(define (compiler-pathnames input-string output-string default transform)
  (let* ((core
	  (lambda (input-string)
	    (let ((input-pathname (merge-pathnames input-string default)))
	      (let ((output-pathname
		     (let ((output-pathname
			    (pathname-new-type input-pathname
					       compiled-output-extension)))
		       (if output-string
			   (merge-pathnames output-string output-pathname)
			   output-pathname))))
		(if compiler:noisy?
		    (begin
		      (newline)
		      (write-string "Compile File: ")
		      (write (enough-namestring input-pathname))
		      (write-string " => ")
		      (write (enough-namestring output-pathname))))
		(compiler-file-output
		 (transform input-pathname output-pathname)
				      output-pathname)))))
	 (kernel
	  (if compiler:batch-mode?
	      (batch-kernel core)
	      core)))
    (if (pair? input-string)
	(for-each kernel input-string)
	(kernel input-string))))

(define (compiler-fasload pathname)
  (let ((scode
	 (let ((scode (fasload pathname)))
	   (if (scode/comment? scode)
	       (scode/comment-expression scode)
	       scode))))
    (if (scode/open-block? scode)
	(scode/open-block-components scode
	  (lambda (names declarations body)
	    (if (null? names)
		(scan-defines body
		  (lambda (names declarations* body)
		    (make-open-block names
				     (append declarations declarations*)
				     body)))
		scode)))
	(scan-defines scode make-open-block))))

;;;; Alternate Entry Points

(define (compile-scode/new scode #!optional keep-debugging-info?)
  keep-debugging-info?			; ignored
  (perhaps-issue-compatibility-warning)
  (compile-scode/%new scode))

(define compatibility-detection-frob (vector #F '()))

(define (perhaps-issue-compatibility-warning)
  (if (eq? (vector-ref compatibility-detection-frob 0)
	   (vector-ref compatibility-detection-frob 1))
      (begin
	(warn "!! You are compiling while in compatibility mode,")
	(warn "!! where #F is the !! same as '().")
	(warn "!! The compiled code will be incorrect for the")
	(warn "!! standard environment."))))

(define (compile-scode/%new scode #!optional keep-debugging-info?)
  keep-debugging-info?			; ignored
  (compiler-output->compiled-expression
   (let* ((kmp-file-name (temporary-file-pathname))
	  (rtl-file-name (temporary-file-pathname))
	  (lap-file-name (temporary-file-pathname))
	  (info-output-pathname false))
     (warn "KMP Output to temporary file" (->namestring kmp-file-name))
     (warn "RTL Output to temporary file" (->namestring rtl-file-name))
     (warn "LAP Output to temporary file" (->namestring lap-file-name))
     (let ((win? false))
       (dynamic-wind
	(lambda () unspecific)
	(lambda ()
	  (call-with-output-file kmp-file-name
	    (lambda (kmp-output-port)
	      (call-with-output-file rtl-file-name
		(lambda (rtl-output-port)
		  (call-with-output-file lap-file-name
		    (lambda (lap-output-port)
		      (let ((result
			     (%compile/new scode
					   false
					   info-output-pathname
					   kmp-output-port
					   rtl-output-port
					   lap-output-port)))
			(set! win? true)
			result))))))))
	(lambda ()
	  (if (not win?)
	      (begin
		(warn "Deleting KMP, RTL and LAP output files")
		(delete-file kmp-file-name)
		(delete-file rtl-file-name)
		(delete-file lap-file-name)))))))))

;; First set: phase/scode->kmp
;; Last used: phase/optimize-kmp
(define *kmp-program*)

;; First set: phase/optimize-kmp
;; Last used: phase/kmp->rtl
(define *optimized-kmp-program*)

;; First set: phase/kmp->rtl
;; Last used: phase/rtl-program->rtl-graph
(define *rtl-program*)
(define *rtl-entry-label*)

(define *argument-registers* '())
(define *use-debugging-info?* true)

(define (%compile/new program
		      recursive?
		      info-output-pathname
		      kmp-output-port
		      rtl-output-port
		      lap-output-port)
  (initialize-machine-register-map!)
  (fluid-let ((*info-output-filename*
	       (if (memq info-output-pathname '(KEEP RECURSIVE))
		   *info-output-filename*
		   info-output-pathname))
	      (*rtl-output-port* rtl-output-port)
	      (*lap-output-port* lap-output-port)
	      (*kmp-output-port* kmp-output-port)
	      (compiler:generate-lap-files? true)
	      (*argument-registers* (rtlgen/argument-registers))
	      (available-machine-registers
	       ;; Order is important!
	       (rtlgen/available-registers available-machine-registers))
	      (*strongly-heed-branch-preferences?* true)
	      (*envconv/compile-by-procedures?*
	       (if compiler:cross-compiling?
		   #F
		   compiler:compile-by-procedures?)))

    ((if recursive?
	 bind-compiler-variables
	 in-compiler)
     (lambda ()
       (set! *current-label-number* 0)
       (within-midend
	 recursive?
	 (lambda ()
	   (if (not recursive?)
	       (begin
		 (set! *input-scode* program)
		 (phase/scode->kmp))
	       (begin
		 (set! *kmp-program* program)))
	   (phase/optimize-kmp recursive?)
	   (phase/kmp->rtl)))
       (if rtl-output-port
	   (phase/rtl-file-output "Original"
				  false
				  false
				  program
				  rtl-output-port
				  *rtl-program*))
       (phase/rtl-program->rtl-graph)
       (if rtl-output-port
	   (phase/rtl-file-output "Unoptimized"
				  false
				  false
				  program
				  rtl-output-port
				  false))
       (phase/rtl-optimization)
       (if rtl-output-port
	   (phase/rtl-file-output "Optimized"
				  true
				  true
				  program
				  rtl-output-port
				  false))
       (phase/lap-generation)
       (phase/lap-linearization)
       (if lap-output-port
	   (phase/lap-file-output program lap-output-port))
       (assemble&link info-output-pathname)))))

(define (phase/scode->kmp)
  (compiler-phase
   "Scode->KMP"
   (lambda ()
     (with-kmp-output-port
      (lambda ()
	(write-string "Input")
	(newline)
	(pp *input-scode*)))
     (set! *kmp-program*
	   (scode->kmp (last-reference *input-scode*)))
     (with-kmp-output-port
      (lambda ()
	(newline)
	(write-char #\Page)
	(newline)
	(write-string "Initial KMP program")
	(newline)
	(fluid-let (;; (*pp-uninterned-symbols-by-name* false)
		    (*pp-primitives-by-name* false))
	  (pp *kmp-program* (current-output-port) true))))
     unspecific)))

(define (phase/optimize-kmp recursive?)
  (compiler-phase
   "Optimize KMP"
   (lambda ()
     (set! *optimized-kmp-program*
	   (optimize-kmp recursive? (last-reference *kmp-program*)))
     (with-kmp-output-port
      (lambda ()
	(newline)
	(write-char #\Page)
	(newline)
	(write-string "Final KMP program ")
	(write *recursive-compilation-number*)
	(if *kmp-output-abbreviated?*
	    (begin
	      (write-string " (*kmp-output-abbreviated?* is #T)")
	      (newline)
	      (kmp/ppp *optimized-kmp-program*))
	    (fluid-let (;; (*pp-uninterned-symbols-by-name* false)
			(*pp-primitives-by-name* false))
	      (newline)
	      (pp *optimized-kmp-program* (current-output-port) true)))))
     unspecific)))

(define (with-kmp-output-port thunk)
  (if *kmp-output-port*
      (begin
	(with-output-to-port *kmp-output-port* thunk)
	(output-port/flush-output *kmp-output-port*))))

(define (phase/kmp->rtl)
  (compiler-phase "KMP->RTL"
   (lambda ()
     (call-with-values
      (lambda ()
	(kmp->rtl (last-reference *optimized-kmp-program*)))
      (lambda (program entry-label)
	(set! *rtl-program* program)
	(set! *rtl-entry-label* entry-label)
	unspecific)))))

(define (phase/rtl-program->rtl-graph)
  (compiler-phase
   "RTL->RTL graph"
   (lambda ()
     (set! *ic-procedure-headers* '())
     (initialize-machine-register-map!)
     (call-with-values
      (lambda ()
	(rtl->rtl-graph (last-reference *rtl-program*)))
      (lambda (expression procedures continuations rgraphs)
	(set! label->object
	      (make/label->object expression
				  procedures
				  continuations))
	(set! *rtl-expression* expression)
	(set! *rtl-procedures* procedures)
	(set! *rtl-continuations* continuations)
	(set! *rtl-graphs* rgraphs)
	(set! *rtl-root*
	      (or expression
		  (label->object *rtl-entry-label*)))
	unspecific)))))

(define compile-bin-file/new
  (make-compile-bin-file
   (lambda (scode info-pathname kmp-port rtl-port lap-port)
     (%compile/new scode
		   false
		   info-pathname
		   kmp-port
		   rtl-port
		   lap-port))))
     
(define cbf/new (make-cbf compile-bin-file/new))
(define cf/new (make-cf compile-bin-file/new))
(define compile-expression/new (make-compile-expression compile-scode/%new))
(define compile-procedure/new (make-compile-procedure compile-scode/%new))

(define (compile-recursively/new kmp-program procedure-result? procedure-name)
  ;; Used by the compiler when it wants to compile subexpressions as
  ;; separate code-blocks.
  ;; (values result must-be-called?)
  (let ((my-number *recursive-compilation-count*)
	(output? (and compiler:show-phases?
		      (not (and procedure-result?
				compiler:show-procedures?)))))

    (define (compile-it)
      ;; (values (compiled-obj . compiled-code-block) must-call-it?)
      (fluid-let ((*recursive-compilation-number* my-number)
		  (*procedure-result?* procedure-result?)
		  (*envconv/procedure-result?*
		   procedure-result?))
	(let ((result
	       (%compile/new kmp-program
			     true
			     (and *info-output-filename*
				  (if (eq? *info-output-filename*
					   'KEEP)
				      'KEEP
				      'RECURSIVE))
			     *kmp-output-port*
			     *rtl-output-port*
			     *lap-output-port*)))
	  (values result (not (eq? procedure-result?
				   *procedure-result?*))))))

    (define (link-it)
      ;; (values compiled-obj must-call-it?)
      (let ((simple-link
	     (lambda ()
	       (with-values compile-it
		 (lambda (compiler-output must-call?)
		   ;; Add compiled code block for later linking
		   (set! *remote-links*
			 (cons (cdr compiler-output)
			       *remote-links*))
		   (values (car compiler-output) must-call?))))))
	(if procedure-result?
	    (if compiler:show-procedures?
		(compiler-phase/visible
		 (string-append
		  "Compiling procedure: "
		  (write-to-string procedure-name))
		 simple-link)
		(simple-link))
	    (fluid-let ((*remote-links* '()))
	      (compile-it)))))

    (set! *recursive-compilation-count* (1+ my-number))
    (if output?
	(begin
	  (newline)
	  (newline)
	  (write-string *output-prefix*)
	  (write-string "*** Recursive compilation ")
	  (write my-number)
	  (write-string " ***")))
    (with-values link-it
      (lambda (value must-call?)
	(if output?
	    (begin
	      (newline)
	      (write-string *output-prefix*)
	      (write-string "*** Done with recursive compilation ")
	      (write my-number)
	      (write-string " ***")
	      (newline)))
	(values value must-call?)))))

;; End of New stuff

(define (compiler:batch-compile input #!optional output)
  (fluid-let ((compiler:batch-mode? true))
    (bind-condition-handler (list condition-type:error)
	compiler:batch-error-handler
      (lambda ()
	(if (default-object? output)
	    (compile-bin-file input)
	    (compile-bin-file input output))))))

(define (compiler:batch-error-handler condition)
  (let ((port (nearest-cmdl/port)))
    (newline port)
    (write-condition-report condition port))
  (compiler:abort false))

(define (compiler:abort value)
  (if (not compiler:abort-handled?)
      (error "Not set up to abort" value))
  (newline)
  (write-string "*** Aborting...")
  (compiler:abort-continuation value))

(define (batch-kernel real-kernel)
  (lambda (input-string)
    (call-with-current-continuation
     (lambda (abort-compilation)
       (fluid-let ((compiler:abort-continuation abort-compilation)
		   (compiler:abort-handled? true))
	 (real-kernel input-string))))))

(define compiler:batch-mode? false)
(define compiler:abort-handled? false)
(define compiler:abort-continuation)

;;;; Global variables

(define *recursive-compilation-count*)
(define *recursive-compilation-number*)
(define *procedure-result?*)
(define *remote-links*)
(define *process-time*)
(define *real-time*)

(define *kmp-output-port* false)
(define *kmp-output-abbreviated?* true)

(define *info-output-filename* false)
(define *rtl-output-port* false)
(define *rtl-output-all-phases?* false)
(define *lap-output-port* false)

;; First set: input to compilation
;; Last used: phase/canonicalize-scode
(define *input-scode*)

;; First set: phase/canonicalize-scode
;; Last used: phase/translate-scode
(define *scode*)

;; First set: phase/translate-scode
;; Last used: phase/fg-optimization-cleanup
(define *root-block*)

;; First set: phase/translate-scode
;; Last used: phase/rtl-generation
(define *root-expression*)
(define *root-procedure*)

;; First set: phase/rtl-generation
;; Last used: phase/lap-linearization
(define *rtl-expression*)
(define *rtl-procedures*)
(define *rtl-continuations*)
(define *rtl-graphs*)
(define label->object)
(define *rtl-root*)

;; First set: phase/rtl-generation
;; Last used: phase/link
(define *ic-procedure-headers*)
(define *entry-label*)

;; First set: phase/lap-generation
;; Last used: phase/link
(define *subprocedure-linking-info*)

;; First set: phase/lap-linearization
;; Last used: phase/assemble
(define *lap*)

;; First set: phase/lap-linearization
;; Last used: phase/info-generation-2
(define *dbg-expression*)
(define *dbg-procedures*)
(define *dbg-continuations*)

(define (in-compiler thunk)
  (let ((run-compiler
	 (lambda ()
	   (let ((value
		  (let ((expression (thunk)))
		    (let ((others
			   (map (lambda (other) (vector-ref other 2))
				(recursive-compilation-results))))
		      (cond ((not (compiled-code-address? expression))
			     (vector compiler:compile-by-procedures?
				     expression
				     others))
			    ((null? others)
			     expression)
			    (else
			     (scode/make-comment
			      (make-dbg-info-vector
			       (let ((all-blocks
				      (list->vector
				       (cons
					(compiled-code-address->block
					 expression)
					others))))
				 (if compiler:compile-by-procedures?
				     (list 'COMPILED-BY-PROCEDURES
					   all-blocks
					   (list->vector others))
				     all-blocks)))
			      expression)))))))
	     (if compiler:show-time-reports?
		 (compiler-time-report "Total compilation time"
				       *process-time*
				       *real-time*))
	     value))))
    (if compiler:preserve-data-structures?
	(begin
	  (compiler:reset!)
	  (run-compiler))
	(fluid-let ((*recursive-compilation-number* 0)
		    (*recursive-compilation-count* 1)
		    (*procedure-result?* false)
		    (*remote-links* '())
		    (*process-time* 0)
		    (*real-time* 0))
	  (bind-assembler&linker-top-level-variables
	   (lambda ()
	     (bind-compiler-variables run-compiler)))))))

(define (bind-compiler-variables thunk)
  ;; Split this fluid-let because compiler was choking on it.
  (fluid-let ((*ic-procedure-headers*)
	      (*current-label-number*)
	      (*dbg-expression*)
	      (*dbg-procedures*)
	      (*dbg-continuations*)
	      (*lap*)
	      (*expressions*)
	      (*procedures*))
    (fluid-let ((*input-scode*)
		(*scode*)
		(*kmp-program*)
		(*optimized-kmp-program*)
		(*rtl-program*)
		(*rtl-entry-label*)
		(*root-expression*)
		(*root-procedure*)
		(*root-block*)
		(*rtl-expression*)
		(*rtl-procedures*)
		(*rtl-continuations*)
		(*rtl-graphs*)
		(label->object)
		(*rtl-root*)
		(*machine-register-map*)
		(*entry-label*)
		(*subprocedure-linking-info*))
      (bind-assembler&linker-variables thunk))))

(define (compiler:reset!)
  (set! *recursive-compilation-number* 0)
  (set! *recursive-compilation-count* 1)
  (set! *procedure-result?* false)
  (set! *remote-links* '())
  (set! *process-time* 0)
  (set! *real-time* 0)

  (set! *ic-procedure-headers*)
  (set! *current-label-number*)
  (set! *dbg-expression*)
  (set! *dbg-procedures*)
  (set! *dbg-continuations*)
  (set! *lap*)
  (set! *expressions*)
  (set! *procedures*)
  (set! *input-scode*)
  (set! *scode*)
  (set! *kmp-program*)
  (set! *optimized-kmp-program*)
  (set! *rtl-program*)
  (set! *rtl-entry-label*)
  (set! *root-expression*)
  (set! *root-procedure*)
  (set! *root-block*)
  (set! *rtl-expression*)
  (set! *rtl-procedures*)
  (set! *rtl-continuations*)
  (set! *rtl-graphs*)
  (set! label->object)
  (set! *rtl-root*)
  (set! *machine-register-map*)
  (set! *entry-label*)
  (set! *subprocedure-linking-info*)
  (assembler&linker-reset!))

(define (compiler-phase name thunk)
  (if compiler:show-phases?
      (compiler-phase/visible name
	(lambda ()
	  (compiler-phase/invisible thunk)))
      (compiler-phase/invisible thunk)))

(define (compiler-superphase name thunk)
  (if compiler:show-subphases?
      (thunk)
      (compiler-phase name thunk)))

(define (compiler-subphase name thunk)
  (if compiler:show-subphases?
      (compiler-phase name thunk)
      (compiler-phase/invisible thunk)))

(define (compiler-phase/visible name thunk)
  (fluid-let ((*output-prefix* (string-append "    " *output-prefix*)))
    (newline)
    (write-string *output-prefix*)
    (write-string name)
    (write-string "...")
    (if compiler:show-time-reports?
	(let ((process-start *process-time*)
	      (real-start *real-time*))
	  (let ((value (thunk)))
	    (compiler-time-report "  Time taken"
				  (- *process-time* process-start)
				  (- *real-time* real-start))
	    value))
	(thunk))))

(define *output-prefix* "")
(define *phase-level* 0)

(define (compiler-phase/invisible thunk)
  (fluid-let ((*phase-level* (1+ *phase-level*)))
    (let ((do-it
	   (if compiler:phase-wrapper
	       (lambda () (compiler:phase-wrapper thunk))
	       thunk)))
      (if (= 1 *phase-level*)
	  (let ((process-start (process-time-clock))
		(real-start (real-time-clock)))
	    (let ((value (do-it)))
	      (let ((process-delta (- (process-time-clock) process-start))
		    (real-delta (- (real-time-clock) real-start)))
		(set! *process-time* (+ process-delta *process-time*))
		(set! *real-time* (+ real-delta *real-time*)))
	      value))
	  (do-it)))))

(define (compiler-time-report prefix process-time real-time)
  (newline)
  (write-string *output-prefix*)
  (write-string prefix)
  (write-string ": ")
  (write (/ (exact->inexact process-time) 1000))
  (write-string " (process time); ")
  (write (/ (exact->inexact real-time) 1000))
  (write-string " (real time)"))

(define (phase/canonicalize-scode)
  (compiler-subphase "Scode Canonicalization"
    (lambda ()
      (set! *scode* (canonicalize/top-level (last-reference *input-scode*)))
      unspecific)))

(define (phase/rtl-optimization)
  (compiler-superphase "RTL Optimization"
    (lambda ()
      (phase/rtl-dataflow-analysis)
      (phase/rtl-rewriting rtl-rewriting:pre-cse)
      (if (and *rtl-output-all-phases?* *rtl-output-port*)
	  (phase/rtl-file-output "Post Rtl-rewriting:pre-cse"
				 false
				 false
				 false
				 *rtl-output-port*
				 false))
      (if compiler:cse?
	  (phase/common-subexpression-elimination))
      (if *rtl-output-port*
	  (phase/rtl-file-output "Post CSE"
				 false
				 false
				 false
				 *rtl-output-port*
				 false))
      (phase/invertible-expression-elimination)
      (if (and *rtl-output-all-phases?* *rtl-output-port*)
	  (phase/rtl-file-output "Post Invertible-Expression-Elimination"
				 false
				 false
				 false
				 *rtl-output-port*
				 false))
      (phase/rtl-rewriting rtl-rewriting:post-cse)
      (phase/common-suffix-merging)
      (phase/linearization-analysis)
      (phase/lifetime-analysis)
      (if (and *rtl-output-all-phases?* *rtl-output-port*)
	  (phase/rtl-file-output "Post Lifetime-Analysis"
				 false
				 false
				 false
				 *rtl-output-port*
				 false))
      (if compiler:code-compression?
	  (phase/code-compression))
      (phase/register-allocation)
      (phase/rtl-optimization-cleanup))))

(define (phase/rtl-dataflow-analysis)
  (compiler-subphase "RTL Dataflow Analysis"
    (lambda ()
      (rtl-dataflow-analysis *rtl-graphs*))))

(define (phase/rtl-rewriting rtl-rewriting)
  (compiler-subphase "RTL Rewriting"
    (lambda ()
      (rtl-rewriting *rtl-graphs*))))

(define (phase/common-subexpression-elimination)
  (compiler-subphase "Common Subexpression Elimination"
    (lambda ()
      (common-subexpression-elimination *rtl-graphs*))))

(define (phase/invertible-expression-elimination)
  (compiler-subphase "Invertible Expression Elimination"
    (lambda ()
      (invertible-expression-elimination *rtl-graphs*))))

(define (phase/common-suffix-merging)
  (compiler-subphase "Common Suffix Merging"
    (lambda ()
      (merge-common-suffixes! *rtl-graphs*))))

(define (phase/lifetime-analysis)
  (compiler-subphase "Lifetime Analysis"
    (lambda ()
      (lifetime-analysis *rtl-graphs*))))

(define (phase/code-compression)
  (compiler-subphase "Instruction Combination"
    (lambda ()
      (code-compression *rtl-graphs*))))

(define (phase/linearization-analysis)
  (compiler-subphase "Linearization Analysis"
    (lambda ()
      (setup-bblock-continuations! *rtl-graphs*))))

(define (phase/register-allocation)
  (compiler-subphase "Register Allocation"
    (lambda ()
      (register-allocation *rtl-graphs*))))

(define (phase/rtl-optimization-cleanup)
  (if (not compiler:preserve-data-structures?)
      (for-each (lambda (rgraph)
		  (set-rgraph-bblocks! rgraph false)
		  ;; **** this slot is reused. ****
		  ;;(set-rgraph-register-bblock! rgraph false)
		  (set-rgraph-register-crosses-call?! rgraph false)
		  (set-rgraph-register-n-deaths! rgraph false)
		  (set-rgraph-register-live-length! rgraph false)
		  (set-rgraph-register-n-refs! rgraph false)
		  (set-rgraph-register-known-values! rgraph false)
		  (set-rgraph-register-known-expressions! rgraph false))
		*rtl-graphs*)))

(define (phase/rtl-file-output class continuations-linked?
			       last-for-this-scode? scode port code)
  (compiler-phase "RTL File Output"
    (lambda ()
      (write-string class port)
      (write-string " RTL for object " port)
      (write *recursive-compilation-number* port)
      (newline port)
      (if scode
	  (begin (pp scode port #t 4)
		 (newline port)
		 (newline port)))
      (write-rtl-instructions (or code
				  (linearize-rtl *rtl-root*
						 *rtl-procedures*
						 *rtl-continuations*
						 continuations-linked?))
			      port)
      (if (or (not (zero? *recursive-compilation-number*))
	      (not last-for-this-scode?))
	  (begin
	    (write-char #\page port)
	    (newline port)))
      (output-port/flush-output port))))

(define (phase/lap-generation)
  (compiler-phase "LAP Generation"
    (lambda ()
      (initialize-back-end!)
      (if *procedure-result?*
	  (generate-lap *rtl-graphs* '()
	    (lambda (prefix environment-label free-ref-label n-sections)
	      (node-insert-snode! (rtl-procedure/entry-node *rtl-root*)
				  (make-sblock prefix))
	      (set! *entry-label*
		    (rtl-procedure/external-label *rtl-root*))
	      (set! *subprocedure-linking-info*
		    (vector environment-label free-ref-label n-sections))
	      unspecific))
	  (begin
	    (let ((prefix (generate-lap *rtl-graphs* *remote-links* false)))
	      (node-insert-snode! (rtl-expr/entry-node *rtl-root*)
				  (make-sblock prefix)))
	    (set! *entry-label* (rtl-expr/label *rtl-root*))
	    unspecific)))))

(define (phase/lap-linearization)
  (compiler-phase "LAP Linearization"
    (lambda ()
      (set! *lap*
	    (optimize-linear-lap
	     (wrap-lap *entry-label*
		       (linearize-lap *rtl-root*
				      *rtl-procedures*
				      *rtl-continuations*
				      true))))
      (if *use-debugging-info?*
	  (with-values
	      (lambda ()
		(info-generation-phase-2 *rtl-expression*
					 *rtl-procedures*
					 *rtl-continuations*))
	    (lambda (expression procedures continuations)
	      (set! *dbg-expression* expression)
	      (set! *dbg-procedures* procedures)
	      (set! *dbg-continuations* continuations)
	      unspecific)))
      (if (not compiler:preserve-data-structures?)
	  (begin
	    (set! *rtl-expression*)
	    (set! *rtl-procedures*)
	    (set! *rtl-continuations*)
	    (set! *rtl-graphs*)
	    (set! label->object)
	    (set! *rtl-root*)
	    unspecific)))))

(define (phase/lap-file-output scode port)
  (compiler-phase "LAP File Output"
    (lambda ()
      (fluid-let ((*unparser-radix* 16)
		  (*unparse-uninterned-symbols-by-name?* true))
	(with-output-to-port port
	  (lambda ()
	    (define (hack-rtl rtl)
	      (if (pair? rtl)
		  (cond ((eq? (car rtl) 'REGISTER)
			 (string->uninterned-symbol
			  (with-output-to-string
			    (lambda () (display "r") (display (cadr rtl))))))
			((eq? (car rtl) 'CONSTANT)
			 rtl)
			(else
			 (map hack-rtl rtl)))
		  rtl))
		  
	    (write-string "LAP for object ")
	    (write *recursive-compilation-number*)
	    (newline)
	    (pp scode (current-output-port) #T 4)
	    (newline)
	    (newline)
	    (newline)
	    (for-each
		(lambda (instruction)
		  (cond ((and (pair? instruction)
			      (eq? (car instruction) 'LABEL))
			 (write (cadr instruction))
			 (write-char #\:))
			((and (pair? instruction)
			      (eq? (car instruction) 'COMMENT))
			 (write-char #\tab)
			 (write-string ";;")
			 (for-each (lambda (frob)
				     (write-string " ")
				     (write (if (and (pair? frob)
						     (eq? (car frob) 'RTL))
						(hack-rtl (cadr frob))
						frob)))
			   (cdr instruction)))
			(else
			 (write-char #\tab)
			 (write instruction)))
		  (newline))
	      *lap*)
	    (if (not (zero? *recursive-compilation-number*))
		(begin
		  (write-char #\page)
		  (newline)))
	    (output-port/flush-output port)))))))

(define compile-bin-file compile-bin-file/new)
(define cbf cbf/new)
(define cf cf/new)
(define compile-expression compile-expression/new)
(define compile-procedure compile-procedure/new)
