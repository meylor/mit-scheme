;;; -*-Scheme-*-
;;;
;;;	$Id: undo.scm,v 1.56 1993/10/05 23:05:35 cph Exp $
;;;
;;;	Copyright (c) 1985, 1989-93 Massachusetts Institute of Technology
;;;
;;;	This material was developed by the Scheme project at the
;;;	Massachusetts Institute of Technology, Department of
;;;	Electrical Engineering and Computer Science.  Permission to
;;;	copy this software, to redistribute it, and to use it for any
;;;	purpose is granted, subject to the following restrictions and
;;;	understandings.
;;;
;;;	1. Any copy made of this software must include this copyright
;;;	notice in full.
;;;
;;;	2. Users of this software agree to make their best efforts (a)
;;;	to return to the MIT Scheme project any improvements or
;;;	extensions that they make, so that these may be included in
;;;	future releases; and (b) to inform MIT of noteworthy uses of
;;;	this software.
;;;
;;;	3. All materials developed as a consequence of the use of this
;;;	software shall duly acknowledge such use, in accordance with
;;;	the usual standards of acknowledging credit in academic
;;;	research.
;;;
;;;	4. MIT has made no warrantee or representation that the
;;;	operation of this software will be error-free, and MIT is
;;;	under no obligation to provide any services, by way of
;;;	maintenance, update, or otherwise.
;;;
;;;	5. In conjunction with products arising from the use of this
;;;	material, there shall be no use of the name of the
;;;	Massachusetts Institute of Technology nor of any adaptation
;;;	thereof in any advertising, promotional, or sales literature
;;;	without prior written consent from MIT in each case.
;;;
;;; NOTE: Parts of this program (Edwin) were created by translation
;;; from corresponding parts of GNU Emacs.  Users should be aware that
;;; the GNU GENERAL PUBLIC LICENSE may apply to these parts.  A copy
;;; of that license should have been included along with this file.
;;;

;;;; Undo, translated from the GNU Emacs implementation in C/Emacs-Lisp.

(declare (usual-integrations))

(define (enable-group-undo! group)
  (set-group-undo-data! group '()))

(define (disable-group-undo! group)
  (set-group-undo-data! group #t))

(define (with-group-undo-disabled group thunk)
  (let ((outside-data)
	(inside-data #t))
    (dynamic-wind (lambda ()
		    (set! outside-data (group-undo-data group))
		    (set-group-undo-data! group inside-data)
		    (set! inside-data)
		    unspecific)
		  thunk
		  (lambda ()
		    (set! inside-data (group-undo-data group))
		    (set-group-undo-data! group outside-data)
		    (set! outside-data)
		    unspecific))))

(define (undo-done! point)
  ;; Called to say that POINT's group should have no undo data,
  ;; usually because it has just been filled from a file.
  (let ((group (mark-group point)))
    (if (not (eq? #t (group-undo-data group)))
	(set-group-undo-data! group '()))))

(define (undo-boundary! point)
  ;; Called to say that M-x undo should consider this the boundary of
  ;; a single undoable sequence of changes.
  (group-undo-boundary! (mark-group point)))

(define (undo-leave-window! window)
  ;; Called to say that WINDOW is being deselected, and that therefore
  ;; this is a good point at which to mark an undo boundary.
  (group-undo-boundary! (buffer-group (window-buffer window))))

(define (group-undo-boundary! group)
  (if (not (or (eq? #t (group-undo-data group))
	       ;; Don't allow a boundary to be inserted as the last
	       ;; element of the list.
	       (null? (group-undo-data group))
	       ;; Don't allow two boundaries to be adjacent.
	       (eq? #f (car (group-undo-data group)))))
      (set-group-undo-data! group (cons #f (group-undo-data group)))))

;;;; Recording Hooks

;;; These recording hooks must be called before GROUP-MODIFIED? is
;;; updated, so that they can read its old value.  In addition, the
;;; deletion recording hook must be called before the deletion is
;;; performed, so that it can extract the characters being deleted.

(define (undo-record-insertion! group start end)
  (cond ((eq? #t (group-undo-data group))
	 unspecific)
	((not (group-modified? group))
	 (undo-record-first-change! group)
	 (set-group-undo-data! group
			       (cons (cons start end)
				     (group-undo-data group))))
	((and (pair? (group-undo-data group))
	      (pair? (car (group-undo-data group)))
	      (fix:fixnum? (caar (group-undo-data group)))
	      (fix:fixnum? (cdar (group-undo-data group)))
	      (fix:= (cdr (group-undo-data group)) start))
	 (set-cdr! (group-undo-data group) end))
	(else
	 (set-group-undo-data! group
			       (cons (cons start end)
				     (group-undo-data group))))))

(define (undo-record-deletion! group start end)
  (if (not (eq? #t (group-undo-data group)))
      (begin
	(if (not (group-modified? group))
	    (undo-record-first-change! group))
	(if (group-text-properties group)
	    (set-group-undo-data!
	     group
	     (cons (cons 'REINSERT-PROPERTIES
			 (group-extract-properties group start end))
		   (group-undo-data group))))
	(set-group-undo-data!
	 group
	 (let ((text (group-extract-string group start end))
	       (point (mark-index (group-point group))))
	   (cond ((fix:= point start)
		  (cons (cons text start)
			(group-undo-data group)))
		 ((fix:= point end)
		  (cons (cons text (fix:- 0 start))
			(group-undo-data group)))
		 (else
		  (cons* (cons text start)
			 point
			 (group-undo-data group)))))))))

(define (undo-record-property-changes! group properties)
    (if (not (eq? #t (group-undo-data group)))
	(begin
	  (if (not (group-modified? group))
	      (undo-record-first-change! group))
	  (set-group-undo-data!
	   group
	   (cons (cons 'REINSERT-PROPERTIES properties)
		 (group-undo-data group))))))

(define (undo-record-first-change! group)
  (let ((buffer (group-buffer group)))
    (if buffer
	(set-group-undo-data! group
			      (cons (cons #t (buffer-modification-time buffer))
				    (group-undo-data group))))))

;;;; Truncation

(define-variable undo-limit
  "Keep no more undo information once it exceeds this size.
This limit is applied when garbage collection happens.
The size is counted as the number of bytes occupied,
which includes both the saved text and other data."
  20000
  exact-nonnegative-integer?)

(define-variable undo-strong-limit
  "Don't keep more than this much size of undo information.
A command that pushes past this size is itself forgotten.
This limit is applied when garbage collection happens.
The size is counted as the number of bytes occupied,
which includes both the saved text and other data."
  30000
  exact-nonnegative-integer?)

(define (truncate-buffer-undo-lists!)
  ;; This procedure must be careful about accessing editor data
  ;; structures because it is a GC daemon and can be run at times when
  ;; the editor does not exist or is not running.  It would actually
  ;; prefer to be run *before* the GC, but that's not possible now.
  (if edwin-editor
      (let ((bytes/word
	     (vector-ref ((ucode-primitive gc-space-status 0)) 0)))
	(let ((words->bytes
	       (lambda (words)
		 (round (/ words bytes/word)))))
	(do ((buffers (bufferset-buffer-list (editor-bufferset edwin-editor))
		      (cdr buffers)))
	    ((null? buffers))
	  (let ((buffer (car buffers)))
	    (truncate-undo-data!
	     (group-undo-data (buffer-group buffer))
	     (words->bytes (ref-variable undo-limit buffer))
	     (words->bytes (ref-variable undo-strong-limit buffer)))))))))

(add-gc-daemon! truncate-buffer-undo-lists!)

(define (truncate-undo-data! undo-data min-size max-size)
  (letrec
      ((loop
	(lambda (undo-data prev size boundary)
	  (cond ((null? undo-data)
		 ;; We've reached the end of the list, so no
		 ;; truncation is needed.
		 unspecific)
		((eq? #f (car undo-data))
		 ;; We've reached a boundary.  If it's the first
		 ;; boundary, continue regardless of size, otherwise
		 ;; continue only if we haven't yet reached MIN-SIZE.
		 (if (and boundary (fix:> size min-size))
		     ;; If we've exceeded MAX-SIZE, truncate at the
		     ;; previous boundary, otherwise truncate here.
		     (set-cdr! (if (fix:> size max-size) boundary prev) '())
		     (loop (cdr undo-data) undo-data (fix:+ size 2) prev)))
		(else
		 ;; Normal case: count the storage used by this element.
		 (loop (cdr undo-data)
		       undo-data
		       (fix:+ size
			      (if (pair? (car undo-data))
				  (fix:+
				   4
				   (let ((a (caar undo-data))
					 (b (cdar undo-data)))
				     (cond ((eq? 'REINSERT-PROPERTIES a)
					    (reinsert-properties-size b))
					   ((string? a)
					    (fix:+ 1 (system-vector-length a)))
					   (else 0))))
				  2))
		       boundary))))))
    (cond ((or (null? undo-data)
	       (eq? #t undo-data))
	   unspecific)
	  ((eq? #f (car undo-data))
	   ;; If list starts with a boundary, skip over it.  We want
	   ;; to include the first non-null undo operation in the
	   ;; result.
	   (loop (cdr undo-data) undo-data 2 #f))
	  (else
	   (loop undo-data #f 0 #f)))))

;;;; M-x undo

(define-command undo
  "Undo some previous changes.
Repeat this command to undo more changes.
A numeric argument serves as a repeat count."
  "*p"
  (let ((command-tag (string-copy "undo")))
    (lambda (argument)
      (if (> argument 0)
	  (let ((buffer (current-buffer)))
	    (let ((auto-saved? (buffer-auto-saved? buffer)))
	      (set-command-message!
	       command-tag
	       (command-message-receive command-tag
		 (lambda (undo-data)
		   (undo-more buffer undo-data argument))
		 (lambda ()
		   (undo-more buffer (undo-start buffer) (+ argument 1)))))
	      (if (and auto-saved? (not (buffer-modified? buffer)))
		  (delete-auto-save-file! buffer))
	      (if (not (typein-window? (current-window)))
		  (message "Undo!"))))))))

(define (undo-start buffer)
  (let ((undo-data (group-undo-data (buffer-group buffer))))
    (if (eq? #t undo-data)
	(editor-error "No undo information in this buffer: "
		      (buffer-name buffer)))
    undo-data))

(define (undo-more buffer undo-data n)
  (let loop ((undo-data undo-data) (n n))
    (if (> n 0)
	(begin
	  (if (null? undo-data)
	      (editor-error "No further undo information: "
			    (buffer-name buffer)))
	  (loop (undo-one-step buffer undo-data) (- n 1)))
	undo-data)))

(define (undo-one-step buffer data)
  ;; Perform one undo step on BUFFER, returning the unused portion of DATA.
  (let ((group (buffer-group buffer))
	(point (mark-left-inserting-copy (buffer-point buffer)))
	(outside-visible-range
	 (lambda ()
	   (editor-error
	    "Changes to be undone are outside visible portion of buffer: "
	    (buffer-name buffer)))))
    (let ((finish
	   (lambda (data)
	     (set-buffer-point! buffer point)
	     (mark-temporary! point)
	     data)))
      (let loop ((data data))
	(if (null? data)
	    (finish data)
	    (let ((element (car data))
		  (data (cdr data)))
	      (if (eq? #f element)
		  ;; #F means boundary: this step is done.
		  (finish data)
		  (begin
		    (cond
		     ;; Fixnum is a point position.
		     ((fix:fixnum? element)
		      (set-mark-index! point element))
		     (else
		      (let ((a (car element))
			    (b (cdr element)))
			(cond ((eq? #t a)
			       ;; (#t . MOD-TIME) means first modification
			       (if (eqv? b (buffer-modification-time buffer))
				   (buffer-not-modified! buffer)))
			      ((eq? 'REINSERT-PROPERTIES a)
			       (group-reinsert-properties! group b))
			      ((fix:fixnum? a)
			       ;; (START . END) means insertion
			       (if (or (fix:< a (group-start-index group))
				       (fix:> a (group-end-index group))
				       (fix:> b (group-end-index group)))
				   (outside-visible-range))
			       (set-mark-index! point a)
			       (group-delete! group a b))
			      ;; (STRING . START) means deletion
			      ((fix:< b 0)
			       ;; negative START means set point at end
			       (let ((b (fix:- 0 b)))
				 (if (or (fix:< b (group-start-index group))
					 (fix:> b (group-end-index group)))
				     (outside-visible-range))
				 (set-mark-index! point b)
				 (group-insert-string! group b a)))
			      (else
			       ;; nonnegative START means set point at start
			       (if (or (fix:< b (group-start-index group))
				       (fix:> b (group-end-index group)))
				   (outside-visible-range))
			       (group-insert-string! group b a)
			       (set-mark-index! point b))))))
		    (loop data)))))))))
