;;; -*-Scheme-*-
;;;
;;; $Id: fileio.scm,v 1.148 1999/12/22 02:48:27 cph Exp $
;;;
;;; Copyright (c) 1986, 1989-1999 Massachusetts Institute of Technology
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
;;; Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

;;;; File <-> Buffer I/O

(declare (usual-integrations))

;;;; Encrypted files

(define-variable enable-encrypted-files
  "If true, encrypted files are automatically decrypted when read,
and recrypted when written.  An encrypted file is identified by the
filename suffix \".bf\"."
  #t
  boolean?)

(define ((read/write-encrypted-file? write?) group pathname)
  (and (ref-variable enable-encrypted-files group)
       (equal? "bf" (pathname-type pathname))
       (blowfish-available?)
       (or write? (blowfish-file? pathname))
       #t))

(define (read-encrypted-file pathname mark)
  (let ((m (string-append "Decrypting file " (->namestring pathname) "...")))
    (message m)
    (call-with-output-mark mark
      (lambda (output)
	(%blowfish-decrypt-file pathname output)))
    ;; Disable auto-save here since we don't want to auto-save the
    ;; unencrypted contents of the encrypted file.
    (local-set-variable! auto-save-default #f (mark-buffer mark))
    (message m "done")))

(define (write-encrypted-file region pathname)
  (let ((m (string-append "Encrypting file " (->namestring pathname) "...")))
    (message m)
    (%blowfish-encrypt-file pathname
			    (make-buffer-input-port (region-start region)
						    (region-end region)))
    (message m "done")))

(define (os-independent/read-file-methods)
  (list (cons (read/write-encrypted-file? #f)
	      (lambda (pathname mark visit?)
		visit?
		(read-encrypted-file pathname mark)))))

(define (os-independent/write-file-methods)
  (list (cons (read/write-encrypted-file? #t)
	      (lambda (region pathname visit?)
		visit?
		(write-encrypted-file region pathname)))))

(define (os-independent/alternate-pathnames group pathname)
  (if (ref-variable enable-encrypted-files group)
      (list (string-append (->namestring pathname) ".bf"))
      '()))

;;;; Special File I/O Methods

(define (r/w-file-methods? objects)
  (and (list? objects)
       (for-all? objects
	 (lambda (object)
	   (and (pair? object)
		(procedure? (car object))
		(procedure? (cdr object)))))))

(define-variable read-file-methods
  "List of alternate methods to be used for reading a file into a buffer.
Each method is a pair of a predicate and a procedure.  The methods are
tried, in order, until one of the predicates is satisfied, at which
point the corresponding procedure is used to read the file.  If none
of the predicates is satisfied, the file is read in the usual way."
  (os/read-file-methods)
  r/w-file-methods?)

(define-variable write-file-methods
  "List of alternate methods to be used for writing a file into a buffer.
Each method is a pair of a predicate and a procedure.  The methods are
tried, in order, until one of the predicates is satisfied, at which
point the corresponding procedure is used to write the file.  If none
of the predicates is satisfied, the file is written in the usual way."
  (os/write-file-methods)
  r/w-file-methods?)

(define (read-file-method group pathname)
  (let loop ((methods (ref-variable read-file-methods group)))
    (and (not (null? methods))
	 (if ((caar methods) group pathname)
	     (cdar methods)
	     (loop (cdr methods))))))

(define (write-file-method group pathname)
  (let loop ((methods (ref-variable write-file-methods group)))
    (and (not (null? methods))
	 (if ((caar methods) group pathname)
	     (cdar methods)
	     (loop (cdr methods))))))

(define (get-pathname-or-alternate group pathname default?)
  (if (file-exists? pathname)
      pathname
      (let loop ((alternates (os/alternate-pathnames group pathname)))
	(cond ((null? alternates)
	       (and default? pathname))
	      ((file-exists? (car alternates))
	       (car alternates))
	      (else
	       (loop (cdr alternates)))))))

;;;; Input

(define (read-buffer buffer pathname visit?)
  (set-buffer-writable! buffer)
  (let ((truename #f)
	(file-error #f)
	(group (buffer-group buffer)))
    ;; Set modified so that file supercession check isn't done.
    (set-group-modified?! group #t)
    (region-delete! (buffer-unclipped-region buffer))
    (set! pathname (get-pathname-or-alternate group pathname #t))
    (call-with-current-continuation
     (lambda (continuation)
       (bind-condition-handler (list condition-type:file-error)
	   (lambda (condition)
	     (set! truename #f)
	     (set! file-error condition)
	     (continuation unspecific))
	 (lambda ()
	   (set! truename (->truename pathname))
	   (%insert-file (buffer-start buffer) truename visit?)
	   (if visit?
	       (set-buffer-modification-time!
		buffer
		(file-modification-time truename)))))))
    (set-buffer-point! buffer (buffer-start buffer))
    (if visit?
	(begin
	  (set-buffer-pathname! buffer pathname)
	  (set-buffer-truename! buffer truename)
	  (set-buffer-save-length! buffer)
	  (buffer-not-modified! buffer)
	  (undo-done! (buffer-point buffer))))
    (if file-error
	(signal-condition file-error))
    truename))

(define (insert-file mark filename)
  (%insert-file
   mark 
   (bind-condition-handler (list condition-type:file-error)
       (lambda (condition)
	 condition
	 (editor-error "File " (->namestring filename) " not found"))
     (lambda ()
       (->truename (get-pathname-or-alternate (mark-group mark) filename #t))))
   #f))

(define-variable read-file-message
  "If true, messages are displayed when files are read into the editor."
  #f
  boolean?)

(define-variable translate-file-data-on-input
  "If true (the default), end-of-line translation is done on file input."
  #t
  boolean?)

(define (%insert-file mark truename visit?)
  (let ((method (read-file-method (mark-group mark) truename)))
    (if method
	(method truename mark visit?)
	(let ((do-it
	       (lambda ()
		 (group-insert-file!
		  (mark-group mark)
		  (mark-index mark)
		  truename
		  (pathname-newline-translation truename)))))
	  (if (ref-variable read-file-message mark)
	      (let ((msg
		     (string-append "Reading file \""
				    (->namestring truename)
				    "\"...")))
		(temporary-message msg)
		(let ((value (do-it)))
		  (temporary-message msg "done")
		  value))
	      (do-it))))))

(define (group-insert-file! group index truename translation)
  (let ((filename (->namestring truename)))
    (let ((channel (file-open-input-channel filename)))
      (let ((length (channel-file-length channel))
	    (buffer
	     (and translation
		  (ref-variable translate-file-data-on-input group)
		  (make-input-buffer channel 4096 translation))))
	(bind-condition-handler (list condition-type:allocation-failure)
	    (lambda (condition)
	      condition
	      (error "File too large to fit in memory:" filename))
	  (lambda ()
	    (without-interrupts
	      (lambda ()
		(prepare-gap-for-insert! group index length)))))
	(let ((n
	       (let ((text (group-text group))
		     (end (fix:+ index length)))
		 (if buffer
		     (fix:- (let loop ((index index))
			      (if (fix:< index end)
				  (let ((n
					 (input-buffer/read-substring
					  buffer text index end)))
				    (if (fix:= n 0)
					index
					(loop (fix:+ index n))))
				  index))
			    index)
		     (channel-read-block channel text index end)))))
	  (if (fix:> n 0)
	      (without-interrupts
		(lambda ()
		  (let ((gap-start* (fix:+ index n)))
		    (undo-record-insertion! group index gap-start*)
		    (finish-group-insert! group index n)))))
	  (channel-close channel)
	  n)))))

;;;; Buffer Mode Initialization

(define (normal-mode buffer find-file?)
  (initialize-buffer-modes! buffer)
  (initialize-buffer-local-variables! buffer find-file?))

(define (initialize-buffer-modes! buffer)
  (set-buffer-major-mode!
   buffer
   (or (let ((mode-name (parse-buffer-mode-header buffer)))
	 (and mode-name
	      (let ((mode (string-table-get editor-modes mode-name)))
		(and mode
		     (mode-major? mode)
		     mode))))
       (let ((pathname (buffer-pathname buffer)))
	 (and pathname
	      (pathname-default-mode pathname buffer)))
       (ref-variable editor-default-mode buffer))))

(define (parse-buffer-mode-header buffer)
  (let ((start (buffer-start buffer)))
    (let ((end (line-end start 0)))
      (let ((start (re-search-forward "-\\*-[ \t]*" start end #f)))
	(and start
	     (re-search-forward "[ \t]*-\\*-" start end #f)
	     (let ((end (re-match-start 0)))
	       (if (not (char-search-forward #\: start end #f))
		   (extract-string start end)
		   (let ((m (re-search-forward "mode:[ \t]*" start end #t)))
		     (and m
			  (extract-string
			   m
			   (if (re-search-forward "[ \t]*;" m end #f)
			       (re-match-start 0)
			       end)))))))))))

(define (pathname-default-mode pathname buffer)
  (let ((pathname
	 (if (member (pathname-type pathname) os/encoding-pathname-types)
	     (->namestring (pathname-new-type pathname #f))
	     pathname)))
    (or (let ((filename (->namestring pathname)))
	  (let loop ((types (ref-variable auto-mode-alist buffer)))
	    (and (not (null? types))
		 (if (re-string-match (caar types) filename)
		     (->mode (cdar types))
		     (loop (cdr types))))))
	(let ((type (pathname-type pathname)))
	  (and (string? type)
	       (let loop
		   ((types (ref-variable file-type-to-major-mode buffer)))
		 (and (not (null? types))
		      (if (string-ci=? type (caar types))
			  (->mode (cdar types))
			  (loop (cdr types))))))))))

(define (string->mode-alist? object)
  (and (alist? object)
       (for-all? object
	 (lambda (association)
	   (and (string? (car association))
		(->mode? (cdr association)))))))

(define (->mode? object)
  (or (mode? object)
      (symbol? object)
      (string? object)))

(define-variable auto-mode-alist
  "Alist of filename patterns vs corresponding major modes.
Each element looks like (REGEXP . MODE).
Visiting a file whose name matches REGEXP causes MODE to be used."
  '()
  string->mode-alist?)

(define-variable file-type-to-major-mode
  "Specifies the major mode for new buffers based on file type.
This is an alist, the cars of which are pathname types,
and the cdrs of which are major modes."
  (os/file-type-to-major-mode)
  string->mode-alist?)

;;;; Local Variable Initialization

(define-variable local-variable-search-limit
  "The maximum number of characters searched when looking for local variables
at the end of a file."
  3000
  exact-nonnegative-integer?)

(define-variable inhibit-local-variables
  "True means query before obeying a file's local-variables list.
This applies when the local-variables list is scanned automatically
after you find a file.  If you explicitly request such a scan with
\\[normal-mode], there is no query, regardless of this variable."
  #f
  boolean?)

(define initialize-buffer-local-variables!
  (let ()

(define (initialize-buffer-local-variables! buffer find-file?)
  (let ((end (buffer-end buffer)))
    (let ((start
	   (with-text-clipped
	    (mark- end (ref-variable local-variable-search-limit) 'LIMIT)
	    end
	    (lambda () (backward-one-page end)))))
      (if start
	  (if (re-search-forward "Edwin Variables:[ \t]*" start end #t)
	      (let ((start (re-match-start 0))
		    (end (re-match-end 0)))
		(if (or (not find-file?)
			(not (ref-variable inhibit-local-variables buffer))
			(prompt-for-confirmation?
			 (string-append
			  "Set local variables as specified at end of "
			  (file-namestring (buffer-pathname buffer)))))
		    (parse-local-variables buffer start end))))))))

(define (parse-local-variables buffer start end)
  (let ((prefix (extract-string (line-start start 0) start))
	(suffix (extract-string end (line-end end 0))))
    (let ((prefix? (not (string-null? prefix)))
	  (suffix? (not (string-null? suffix))))
      (define (loop mark)
	(let ((start (line-start mark 1)))
	  (if (not start) (editor-error "Missing local variables entry"))
	  (do-line start (line-end start 0))))

      (define (do-line start end)
	(define (check-suffix mark)
	  (if (and suffix? (not (match-forward suffix mark)))
	      (editor-error "Local variables entry missing suffix")))
	(let ((m1
	       (horizontal-space-end
		(if prefix?
		    (or (match-forward prefix start end #f)
			(editor-error "Local variables entry missing prefix"))
		    start))))
	  (let ((m2
		 (let ((m2 (char-search-forward #\: m1 end)))
		   (if (not m2)
		       (editor-error "Missing colon in local variables entry"))
		   (mark-1+ m2))))
	    (let ((var (extract-string m1 (horizontal-space-start m2)))
		  (m3 (horizontal-space-end (mark1+ m2))))
	      (if (not (string-ci=? var "End"))
		  (with-input-from-mark m3 read
		    (lambda (val m4)
		      (check-suffix (horizontal-space-end m4))
		      (if (string-ci=? var "Mode")
			  (let ((mode
				 (string-table-get editor-modes
						   (extract-string m3 m4))))
			    (if mode
				((if (mode-major? mode)
				     set-buffer-major-mode!
				     enable-buffer-minor-mode!)
				 buffer mode)))
			  (call-with-current-continuation
			   (lambda (continuation)
			     (bind-condition-handler
				 (list condition-type:error)
				 (lambda (condition)
				   condition
				   (editor-beep)
				   (message
				    "Error while processing local variable: "
				    var)
				   (continuation #f))
			       (lambda ()
				 (if (string-ci=? var "Eval")
				     (evaluate val)
				     (define-variable-local-value! buffer
					 (name->variable var)
				       (evaluate val))))))))
		      (loop m4))))))))

      (loop start))))

(define (evaluate sexp)
  (scode-eval (syntax sexp edwin-syntax-table) edwin-environment))

(define edwin-environment
  (->environment '(edwin)))

initialize-buffer-local-variables!))

;;;; Output

(define-variable require-final-newline
  "True says silently put a newline at the end whenever a file is saved.
False means don't add newlines."
  #f
  boolean?)

(define-variable make-backup-files
  "Create a backup of each file when it is saved for the first time.
This can be done by renaming the file or by copying.

Renaming means that Edwin renames the existing file so that it is a
backup file, then writes the buffer into a new file.  Any other names
that the old file had will now refer to the backup file.
The new file is owned by you and its group is defaulted.

Copying means that Edwin copies the existing file into the backup
file, then writes the buffer on top of the existing file.  Any other
names that the old file had will now refer to the new (edited) file.
The file's owner and group are unchanged.

The choice of renaming or copying is controlled by the variables
backup-by-copying ,  backup-by-copying-when-linked  and
backup-by-copying-when-mismatch ."
  #t
  boolean?)

(define-variable backup-by-copying
  "True means always use copying to create backup files.
See documentation of variable  make-backup-files."
  #f
  boolean?)

(define-variable file-precious-flag
  "True means protect against I/O errors while saving files.
Some modes set this true in particular buffers."
  #f
  boolean?)

(define-variable trim-versions-without-asking
  "True means delete excess backup versions silently.
Otherwise asks confirmation."
  #f
  boolean?)

(define-variable write-file-hooks
  "List of procedures to be called before writing out a buffer to a file.
If one of them returns true, the file is considered already written
and the rest are not called."
  '()
  list?)

(define-variable enable-emacs-write-file-message
  "If true, generate Emacs-style message when writing files.
Otherwise, a message is written both before and after long file writes."
  #f
  boolean?)

(define-variable translate-file-data-on-output
  "If true (the default), end-of-line translation is done on file output."
  #t
  boolean?)

(define (write-buffer-interactive buffer backup-mode)
  (let ((pathname (buffer-pathname buffer)))
    (let ((writable? (file-writable? pathname)))
      (if (or writable?
	      (prompt-for-yes-or-no?
	       (string-append "File "
			      (file-namestring pathname)
			      " is write-protected; try to save anyway"))
	      (editor-error
	       "Attempt to save to a file which you aren't allowed to write"))
	  (begin
	    (if (not (or (verify-visited-file-modification-time? buffer)
			 (not (file-exists? pathname))
			 (prompt-for-yes-or-no?
			  "Disk file has changed since visited or saved.  Save anyway")))
		(editor-error "Save not confirmed"))
	    (let ((modes (backup-buffer! buffer pathname backup-mode)))
	      (require-newline buffer)
	      (cond ((let loop ((hooks (ref-variable write-file-hooks buffer)))
		       (and (not (null? hooks))
			    (or ((car hooks) buffer)
				(loop (cdr hooks)))))
		     unspecific)
		    ((ref-variable file-precious-flag buffer)
		     (let ((old (os/precious-backup-pathname pathname)))
		       (let ((rename-back?
			      (catch-file-errors (lambda () #f)
				(lambda ()
				  (rename-file pathname old)
				  (set! modes (file-modes old))
				  #t))))
			 (unwind-protect
			  #f
			  (lambda ()
			    (clear-visited-file-modification-time! buffer)
			    (write-buffer buffer)
			    (if rename-back?
				(begin
				  (set! rename-back? #f)
				  (delete-file-no-errors old))))
			  (lambda ()
			    (if rename-back?
				(begin
				  (rename-file old pathname)
				  (clear-visited-file-modification-time!
				   buffer))))))))
		    (else
		     (if (and (not writable?)
			      (not modes)
			      (file-exists? pathname))
			 (bind-condition-handler
			     (list condition-type:file-error)
			     (lambda (condition)
			       condition
			       (editor-error
				"Can't get write permission for file: "
				(->namestring pathname)))
			   (lambda ()
			     (let ((m (file-modes pathname)))
			       (os/set-file-modes-writable! pathname)
			       (set! modes m)))))
		     (write-buffer buffer)))
	      (if modes
		  (catch-file-errors
		   (lambda () unspecific)
		   (lambda ()
		     (os/restore-modes-to-updated-file! pathname
							modes))))))))))

(define (verify-visited-file-modification-time? buffer)
  (let ((truename (buffer-truename buffer))
	(buffer-time (buffer-modification-time buffer)))
    (or (not truename)
	(not buffer-time)
	(let ((file-time (file-modification-time truename)))
	  (and file-time (< (abs (- buffer-time file-time)) 2))))))

(define-integrable (clear-visited-file-modification-time! buffer)
  (set-buffer-modification-time! buffer #f))

(define (write-buffer buffer)
  (let ((truename
	 (->pathname
	  (write-region (buffer-unclipped-region buffer)
			(buffer-pathname buffer)
			'VISIT
			'DEFAULT))))
    (set-buffer-truename! buffer truename)
    (delete-auto-save-file! buffer)
    (set-buffer-save-length! buffer)
    (buffer-not-modified! buffer)
    (set-buffer-modification-time! buffer (file-modification-time truename))))

(define (write-region region pathname message? translate?)
  (write-region* region pathname message? #f translate?))

(define (append-to-file region pathname message? translate?)
  (write-region* region pathname message? #t translate?))

(define (write-region* region pathname message? append? translate?)
  (let* ((group (region-group region))
	 (start (region-start-index region))
	 (end (region-end-index region))
	 (translate?
	  (if (eq? 'DEFAULT translate?)
	      (ref-variable translate-file-data-on-output group)
	      translate?))
	 (translation (and translate? (pathname-newline-translation pathname)))
	 (filename (->namestring pathname))
	 (method (write-file-method group pathname)))
    (if method
	(if append?
	    (let ((rmethod (read-file-method group pathname)))
	      (if (not rmethod)
		  (error "Can't append: no read method:" pathname))
	      (call-with-temporary-buffer " append region"
		(lambda (buffer)
		  (local-set-variable!
		   translate-file-data-on-input
		   (ref-variable translate-file-data-on-input buffer)
		   buffer)
		  (local-set-variable! translate-file-data-on-output
				       translate?
				       buffer)
		  (rmethod pathname (buffer-start buffer) #f)
		  (insert-region (region-start region)
				 (region-end region)
				 (buffer-end buffer))
		  (method (buffer-region buffer) pathname #f))))
	    (method region pathname (eq? 'VISIT message?)))
	(let ((do-it
	       (lambda ()
		 (if append?
		     (group-append-to-file translation group start end
					   filename)
		     (group-write-to-file translation group start end
					  filename)))))
	  (cond ((not message?)
		 (do-it))
		((or (ref-variable enable-emacs-write-file-message)
		     (<= (- end start) 50000))
		 (do-it)
		 (message "Wrote " filename))
		(else
		 (let ((msg
			(string-append "Writing file " filename "...")))
		   (message msg)
		   (do-it)
		   (message msg "done"))))))
    ;; This isn't the correct truename on systems that support version
    ;; numbers.  For those systems, the truename must be supplied by
    ;; the operating system after the channel is closed.
    filename))

(define (group-write-to-file translation group start end filename)
  (let ((channel (file-open-output-channel filename)))
    (group-write-to-channel translation group start end channel)
    (channel-close channel)))

(define (group-append-to-file translation group start end filename)
  (let ((channel (file-open-append-channel filename)))
    (group-write-to-channel translation group start end channel)
    (channel-close channel)))

(define (group-write-to-channel translation group start end channel)
  (let ((buffer
	 (and translation (make-output-buffer channel 4096 translation))))
    (%group-write group start end
		  (if buffer
		      (lambda (string start end)
			(output-buffer/write-substring-block buffer
							     string start end))
		      (lambda (string start end)
			(channel-write-block channel string start end))))
    (if buffer
	(output-buffer/drain-block buffer))))

(define (group-write-to-port group start end port)
  (%group-write group start end
		(lambda (string start end)
		  (output-port/write-substring port string start end))))

(define (%group-write group start end writer)
  (let ((text (group-text group))
	(gap-start (group-gap-start group))
	(gap-end (group-gap-end group))
	(gap-length (group-gap-length group)))
    (cond ((fix:<= end gap-start)
	   (writer text start end))
	  ((fix:<= gap-start start)
	   (writer text (fix:+ start gap-length) (fix:+ end gap-length)))
	  (else
	   (writer text start gap-start)
	   (writer text gap-end (fix:+ end gap-length))))))

(define (require-newline buffer)
  (let ((require-final-newline? (ref-variable require-final-newline buffer)))
    (if require-final-newline?
	(with-text-clipped (buffer-absolute-start buffer)
			   (buffer-absolute-end buffer)
	  (lambda ()
	    (let ((end (buffer-end buffer)))
	      (if (let ((last-char (extract-left-char end)))
		    (and last-char
			 (not (eqv? #\newline last-char))
			 (or (eq? require-final-newline? #t)
			     (prompt-for-yes-or-no?
			      (string-append
			       "Buffer " (buffer-name buffer)
			       " does not end in newline.  Add one")))))
		  (insert-newline end))))))))

(define (backup-buffer! buffer truename backup-mode)
  (and (ref-variable make-backup-files buffer)
       (or (memq backup-mode '(BACKUP-PREVIOUS BACKUP-BOTH))
	   (and (not (eq? backup-mode 'NO-BACKUP))
		(not (buffer-backed-up? buffer))))
       truename
       (file-exists? truename)
       (os/backup-buffer? truename)
       (let ((truename (file-chase-links truename)))
	 (catch-file-errors
	  (lambda () #f)
	  (lambda ()
	    (call-with-values
		(lambda () (os/buffer-backup-pathname truename buffer))
	      (lambda (backup-pathname targets)
		(let ((modes
		       (catch-file-errors
			(lambda ()
			  (let ((filename (os/default-backup-filename)))
			    (temporary-message
			     "Cannot write backup file; backing up in "
			     filename)
			    (delete-file-no-errors filename)
			    (copy-file truename filename)
			    #f))
			(lambda ()
			  (delete-file-no-errors backup-pathname)
			  (if (or (ref-variable file-precious-flag buffer)
				  (ref-variable backup-by-copying buffer)
				  (os/backup-by-copying? truename buffer))
			      (begin
				(copy-file truename backup-pathname)
				#f)
			      (begin
				(rename-file truename backup-pathname)
				(file-modes backup-pathname)))))))
		  (set-buffer-backed-up?!
		   buffer
		   (not (memv backup-mode '(BACKUP-NEXT BACKUP-BOTH))))
		  (if (and (not (null? targets))
			   (or (ref-variable trim-versions-without-asking
					     buffer)
			       (prompt-for-confirmation?
				(string-append
				 "Delete excess backup versions of "
				 (->namestring (buffer-pathname buffer))))))
		      (for-each delete-file-no-errors targets))
		  modes))))))))

(define (file-chase-links pathname)
  (let ((contents (file-symbolic-link? pathname)))
    (if contents
	(file-chase-links
	 (pathname-simplify
	  (merge-pathnames contents (directory-pathname pathname))))
	pathname)))