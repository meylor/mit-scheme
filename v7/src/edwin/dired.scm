;;; -*-Scheme-*-
;;;
;;;	$Id: dired.scm,v 1.142 1994/03/10 00:50:31 cph Exp $
;;;
;;;	Copyright (c) 1986, 1989-94 Massachusetts Institute of Technology
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

;;;; Directory Editor
;; package: (edwin dired)

(declare (usual-integrations))

(define-major-mode dired read-only "Dired"
  "Mode for \"editing\" directory listings.
In dired, you are \"editing\" a list of the files in a directory.
You can move using the usual cursor motion commands.
Letters no longer insert themselves.
Instead, type d to flag a file for Deletion.
Type u to Unflag a file (remove its D or C flag).
  Type Rubout to back up one line and unflag.
Type x to eXecute the deletions requested.
Type f to Find the current line's file
  (or Dired it, if it is a directory).
Type o to find file or dired directory in Other window.
Type # to flag temporary files (names beginning with #) for Deletion.
Type ~ to flag backup files (names ending with ~) for Deletion.
Type . to flag numerical backups for Deletion.
  (Spares dired-kept-versions or its numeric argument.)
Type r to rename a file.
Type c to copy a file.
Type g to read the directory again.  This discards all deletion-flags.
Space and Rubout can be used to move down and up by lines.
Also:
 M, G, O -- change file's mode, group or owner.
 C -- compress this file.  U -- uncompress this file.
 K -- encrypt/decrypt this file."
;;Type v to view a file in View mode, returning to Dired when done.
  (lambda (buffer)
    (define-variable-local-value! buffer (ref-variable-object case-fold-search)
      false)
    (event-distributor/invoke! (ref-variable dired-mode-hook buffer) buffer)))

(define-variable dired-mode-hook
  "An event distributor that is invoked when entering Dired mode."
  (make-event-distributor))

(define-key 'dired #\r 'dired-do-rename)
(define-key 'dired #\c-d 'dired-flag-file-deletion)
(define-key 'dired #\d 'dired-flag-file-deletion)
(define-key 'dired #\v 'dired-view-file)
(define-key 'dired #\e 'dired-find-file)
(define-key 'dired #\f 'dired-find-file)
(define-key 'dired #\m 'dired-mark)
(define-key 'dired #\o 'dired-find-file-other-window)
(define-key 'dired #\u 'dired-unmark)
(define-key 'dired #\x 'dired-do-deletions)
(define-key 'dired #\rubout 'dired-backup-unmark)
(define-key 'dired #\? 'dired-summary)
(define-key 'dired #\c 'dired-do-copy)
(define-key 'dired #\# 'dired-flag-auto-save-files)
(define-key 'dired #\~ 'dired-flag-backup-files)
(define-key 'dired #\. 'dired-clean-directory)
(define-key 'dired #\h 'describe-mode)
(define-key 'dired #\space 'dired-next-line)
(define-key 'dired #\c-n 'dired-next-line)
(define-key 'dired #\c-p 'dired-previous-line)
(define-key 'dired #\n 'dired-next-line)
(define-key 'dired #\p 'dired-previous-line)
(define-key 'dired #\g 'dired-revert)
(define-key 'dired #\C 'dired-compress)
(define-key 'dired #\U 'dired-uncompress)
(define-key 'dired #\M 'dired-chmod)
(define-key 'dired #\G 'dired-chgrp)
(define-key 'dired #\O 'dired-chown)
(define-key 'dired #\q 'dired-quit)
(define-key 'dired #\K 'dired-krypt-file)
(define-key 'dired #\c-\] 'dired-abort)
(let-syntax ((define-function-key
               (macro (mode key command)
                 (let ((token (if (pair? key) (car key) key)))
                   `(if (not (lexical-unreferenceable? (the-environment)
                                                       ',token))
                        (define-key ,mode ,key ,command))))))
  (define-function-key 'dired down 'dired-next-line)
  (define-function-key 'dired up 'dired-previous-line))

(define-command dired
  "\"Edit\" directory DIRNAME--delete, rename, print, etc. some files in it.
Dired displays a list of files in DIRNAME.
You can move around in it with the usual commands.
You can flag files for deletion with C-d
and then delete them by typing `x'.
Type `h' after entering dired for more info."
  "DDired (directory)"
  (lambda (directory)
    (select-buffer (make-dired-buffer directory))))

(define-command dired-other-window
  "\"Edit\" directory DIRNAME.  Like \\[dired] but selects in another window."
  "DDired in other window (directory)"
  (lambda (directory)
    (select-buffer-other-window (make-dired-buffer directory))))

(define (make-dired-buffer directory)
  (let ((directory (pathname-simplify directory)))
    (let ((buffer (get-dired-buffer directory)))
      (set-buffer-major-mode! buffer (ref-mode-object dired))
      (set-buffer-default-directory! buffer (directory-pathname directory))
      (buffer-put! buffer 'REVERT-BUFFER-METHOD revert-dired-buffer)
      (buffer-put! buffer 'DIRED-DIRECTORY directory)
      (fill-dired-buffer! buffer directory)
      buffer)))

(define (get-dired-buffer directory)
  (or (list-search-positive (buffer-list)
	(lambda (buffer)
	  (equal? directory (buffer-get buffer 'DIRED-DIRECTORY))))
      (new-buffer (pathname->buffer-name directory))))

(define (dired-buffer-directory buffer)
  (or (buffer-get buffer 'DIRED-DIRECTORY)
      (let ((directory (buffer-default-directory buffer)))
	(buffer-put! buffer 'DIRED-DIRECTORY directory)
	directory)))

(define (revert-dired-buffer buffer dont-use-auto-save? dont-confirm?)
  dont-use-auto-save? dont-confirm?	;ignore
  (let ((lstart (line-start (current-point) 0)))
    (let ((filename
	   (and (dired-filename-start lstart)
		(region->string (dired-filename-region lstart)))))
      (fill-dired-buffer! buffer (dired-buffer-directory buffer))
      (set-current-point!
       (line-start
	(or (and filename
		 (re-search-forward (string-append " "
						   (re-quote-string filename)
						   "\\( -> \\|$\\)")
				    (buffer-start buffer)
				    (buffer-end buffer)
				    false))
	    (if (mark< lstart (buffer-end buffer))
		lstart
		(buffer-end buffer)))
	0)))))

(define-variable dired-kept-versions
  "When cleaning directory, number of versions to keep."
  2
  exact-nonnegative-integer?)

(define (fill-dired-buffer! buffer pathname)
  (set-buffer-writable! buffer)
  (region-delete! (buffer-region buffer))
  (temporary-message
   (string-append "Reading directory " (->namestring pathname) "..."))
  (read-directory pathname
		  (ref-variable dired-listing-switches buffer)
		  (buffer-point buffer))
  (append-message "done")
  (let ((point (mark-left-inserting-copy (buffer-point buffer)))
	(group (buffer-group buffer)))
    (let ((index (mark-index (buffer-start buffer))))
      (if (not (group-end-index? group index))
	  (let loop ((index index))
	    (set-mark-index! point index)
	    (group-insert-string! group index "  ")
	    (let ((index (1+ (line-end-index group (mark-index point)))))
	      (if (not (group-end-index? group index))
		  (loop index)))))))
  (set-buffer-point! buffer (buffer-start buffer))
  (buffer-not-modified! buffer)
  (set-buffer-read-only! buffer))

(define (add-dired-entry pathname)
  (let ((lstart (line-start (current-point) 0))
	(directory (directory-pathname pathname)))
    (if (pathname=? (buffer-default-directory (mark-buffer lstart))
		    directory)
	(insert-dired-entry! pathname directory lstart))))

(define-command dired-find-file
  "Read the current file into a buffer."
  ()
  (lambda ()
    (find-file (dired-current-pathname))))

(define-command dired-find-file-other-window
  "Read the current file into a buffer in another window."
  ()
  (lambda ()
    (find-file-other-window (dired-current-pathname))))

(define-command dired-revert
  "Read the current buffer."
  ()
  (lambda ()
    (revert-buffer (current-buffer) true true)))

(define-command dired-flag-file-deletion
  "Mark the current file to be killed."
  "p"
  (lambda (argument)
    (dired-mark dired-flag-delete-char argument)))

(define-command dired-mark
  "Mark the current (or next ARG) files."
  "p"
  (lambda (argument)
    (dired-mark dired-marker-char argument)))

(define-command dired-unmark
  "Unmark the current (or next ARG) files."
  "p"
  (lambda (argument)
    (dired-mark #\space argument)))

(define-command dired-backup-unmark
  "Move up one line and remove deletion flag there.
Optional prefix ARG says how many lines to unflag; default is one line."
  "p"
  (lambda (argument)
    (dired-mark-backward #\space argument)))

(define-command dired-next-line
  "Move down to the next line."
  "p"
  (lambda (argument)
    (set-dired-point! (line-start (current-point) argument 'BEEP))))

(define-command dired-previous-line
  "Move up to the previous line."
  "p"
  (lambda (argument)
    (set-dired-point! (line-start (current-point) (- argument) 'BEEP))))

(define-command dired-do-deletions
  "Kill all marked files."
  ()
  (lambda ()
    (dired-kill-files)))

(define-command dired-quit
  "Exit Dired, offering to kill any files first."
  ()
  (lambda ()
    (dired-kill-files)
    (kill-buffer-interactive (current-buffer))))

(define-command dired-abort
  "Exit Dired."
  ()
  (lambda ()
    (kill-buffer-interactive (current-buffer))))

(define-command dired-summary
  "Summarize the Dired commands in the typein window."
  ()
  (lambda ()
    (message "d-elete, u-ndelete, x-ecute, q-uit, f-ind, o-ther window")))

(define-command dired-flag-auto-save-files
  "Flag for deletion files whose names suggest they are auto save files."
  ()
  (lambda ()
    (for-each-file-line (current-buffer)
      (lambda (lstart)
	(if (os/auto-save-filename?
	     (region->string (dired-filename-region lstart)))
	    (dired-mark-1 lstart dired-flag-delete-char))))))

(define-command dired-flag-backup-files
  "Flag all backup files for deletion."
  ()
  (lambda ()
    (for-each-file-line (current-buffer)
      (lambda (lstart)
	(if (os/backup-filename?
	     (region->string (dired-filename-region lstart)))
	    (dired-mark-1 lstart dired-flag-delete-char))))))

(define-command dired-clean-directory
  "Flag numerical backups for deletion.
Spares dired-kept-versions latest versions, and kept-old-versions oldest.
Positive numeric arg overrides dired-kept-versions;
negative numeric arg overrides kept-old-versions with minus the arg."
  "P"
  (lambda (argument)
    (let ((argument (command-argument-value argument))
	  (old (ref-variable kept-old-versions))
	  (new (ref-variable dired-kept-versions))
	  (do-it
	   (lambda (old new)
	     (let ((total (+ old new)))
	       (for-each
		(lambda (file)
		  (let ((nv (length (cdr file))))
		    (if (> nv total)
			(let ()
			  (let ((end (- nv total)))
			    (do ((versions
				  (list-tail
				   (sort (cdr file)
					 (lambda (x y)
					   (< (car x) (car y))))
				   old)
				  (cdr versions))
				 (index 0 (fix:+ index 1)))
				((fix:= index end))
			      (dired-mark-1 (cdar versions)
					    dired-flag-delete-char)))))))
		(dired-numeric-backup-files))))))
      (cond ((and argument (> argument 0)) (do-it old argument))
	    ((and argument (< argument 0)) (do-it (- argument) new))
	    (else (do-it old new))))))

(define (dired-numeric-backup-files)
  (let ((result '()))
    (let loop ((start (line-start (buffer-start (current-buffer)) 0)))
      (let ((next (line-start start 1 #f)))
	(if next
	    (begin
	      (let ((region (dired-filename-region start)))
		(if region
		    (let ((filename (region->string region)))
		      (let ((root.version
			     (os/numeric-backup-filename? filename)))
			(if root.version
			    (let ((root (car root.version))
				  (version.index
				   (cons (cdr root.version) start)))
			      (let ((entry (assoc root result)))
				(if entry
				    (set-cdr! entry
					      (cons version.index (cdr entry)))
				    (set! result
					  (cons (list root version.index)
						result))))))))))
	      (loop next)))))
    result))

;;;; File Operation Commands

(define-command dired-do-copy
  "Copy all marked (or next ARG) files, or copy the current file.
This normally preserves the last-modified date when copying.
When operating on just the current file, you specify the new name.
When operating on multiple or marked files, you specify a directory
and new copies are made in that directory
with the same names that the files currently have."
  "P"
  (lambda (argument)
    (dired-create-files
     argument "copy" "copies"
     (dired-create-file-operation
      (lambda (from to)
	(if (ref-variable dired-copy-preserve-time)
	    (let ((access-time (file-access-time from))
		  (modification-time (file-modification-time from)))
	      (copy-file from to)
	      (set-file-times! to access-time modification-time))
	    (copy-file from to)))))))

(define-variable dired-copy-preserve-time
  "If true, Dired preserves the last-modified time in a file copy.
\(This works on only some systems.)"
  #t
  boolean?)

(define-command dired-do-rename
  "Rename current file or all marked (or next ARG) files.
When renaming just the current file, you specify the new name.
When renaming multiple or marked files, you specify a directory."
  "P"
  (lambda (argument)
    (dired-create-files
     argument "rename" "renames"
     (let ((rename (dired-create-file-operation rename-file)))
       (lambda (lstart from to)
	 (let ((condition (rename lstart from to)))
	   (if (not condition)
	       (dired-redisplay to lstart))
	   condition))))))

(define (dired-create-file-operation operation)
  (lambda (lstart from to)
    (call-with-current-continuation
     (lambda (continuation)
       (bind-condition-handler (list condition-type:file-error
				     condition-type:port-error)
	   continuation
	 (lambda ()
	   (dired-handle-overwrite to)
	   (operation from to)
	   (if (char=? dired-marker-char (mark-right-char lstart))
	       (dired-mark-1 lstart #\space))
	   #f))))))

(define (dired-handle-overwrite to)
  (if (and (file-exists? to)
	   (ref-variable dired-backup-overwrite)
	   (or (eq? 'ALWAYS (ref-variable dired-backup-overwrite))
	       (prompt-for-confirmation?
		(string-append "Make backup for existing file `"
			       (->namestring to)
			       "'"))))
      (call-with-values (lambda () (os/buffer-backup-pathname to))
	(lambda (backup-pathname targets)
	  targets
	  (rename-file to backup-pathname)))))

(define-variable dired-backup-overwrite
  "True if Dired should ask about making backups before overwriting files.
Special value `always' suppresses confirmation."
  #f
  boolean?)

(define (dired-create-files argument singular-verb plural-verb operation)
  (let ((filenames
	 (if argument
	     (dired-next-files (command-argument-value argument))
	     (let ((files (dired-marked-files)))
	       (if (null? files)
		   (dired-next-files 1)
		   files)))))
    (cond ((null? filenames)
	   (message "No files to " (string-downcase singular-verb) "."))
	  ((null? (cdr filenames))
	   (dired-create-one-file (cdar filenames) (caar filenames)
				  singular-verb operation))
	  (else
	   (dired-create-many-files filenames
				    singular-verb plural-verb operation)))))

(define (dired-create-one-file lstart from singular-verb operation)
  (let ((to
	 (prompt-for-pathname (string-append (string-capitalize singular-verb)
					     " "
					     (file-namestring from)
					     " to")
			      from
			      #f)))
    (let ((condition
	   (operation lstart from
		      (if (file-directory? to)
			  (merge-pathnames (file-pathname from)
					   (pathname-as-directory to))
			  to))))
      (if condition
	  (editor-error (string-capitalize singular-verb)
			" failed: "
			(condition/report-string condition))))))

(define (dired-create-many-files filenames singular-verb plural-verb operation)
  (let ((destination
	 (pathname-directory
	  (cleanup-pop-up-buffers
	   (lambda ()
	     (let ((buffer (temporary-buffer " *dired-files*")))
	       (write-strings-densely (map (lambda (filename)
					     (file-namestring (car filename)))
					   filenames)
				      (mark->output-port (buffer-point buffer))
				      (window-x-size (current-window)))
	       (set-buffer-point! buffer (buffer-start buffer))
	       (buffer-not-modified! buffer)
	       (set-buffer-read-only! buffer)
	       (define-variable-local-value! buffer
		   (ref-variable-object truncate-partial-width-windows)
		 #f)
	       (pop-up-buffer buffer #f))
	     (prompt-for-existing-directory
	      (string-append (string-capitalize singular-verb)
			     " these files to directory")
	      #f))))))
    (let loop ((filenames filenames) (failures '()))
      (cond ((not (null? filenames))
	     (loop (cdr filenames)
		   (if (operation (cdar filenames)
				  (caar filenames)
				  (pathname-new-directory (caar filenames)
							  destination))
		       (cons (file-namestring (caar filenames)) failures)
		       failures)))
	    ((not (null? failures))
	     (message (string-capitalize plural-verb)
		      " failed: "
		      (reverse! failures)))))))

;;;; Krypt File

(define-command dired-krypt-file
  "Krypt/unkrypt a file.  If the file ends in KY, assume it is already
krypted and unkrypt it.  Otherwise, krypt it."
  '()
  (lambda ()
    (load-option 'krypt)
    (let ((pathname (dired-current-pathname)))
      (if (and (pathname-type pathname)
	       (string=? (pathname-type pathname) "KY"))
	  (dired-decrypt-file pathname)
	  (dired-encrypt-file pathname)))))

(define (dired-decrypt-file pathname)
  (let ((the-encrypted-file
	 (with-input-from-file pathname
	   (lambda ()
	     (read-string (char-set)))))
	(password
	 (prompt-for-password "Password: ")))
    (let ((the-string
	   (decrypt the-encrypted-file password
		    (lambda ()
		      (editor-beep)
		      (message "krypt: Password error!")
		      'FAIL)
		    (lambda (x)
		      x
		      (editor-beep)
		      (message "krypt: Checksum error!")
		      'FAIL))))
      (if (not (eq? the-string 'FAIL))
	  (let ((new-name (pathname-new-type pathname false)))
	    (with-output-to-file new-name
	      (lambda ()
		(write-string the-string)))
	    (delete-file pathname)
	    (dired-redisplay new-name))))))

(define (dired-encrypt-file pathname)
  (let ((the-file-string
	 (with-input-from-file pathname
	   (lambda ()
	     (read-string (char-set)))))
	(password
	 (prompt-for-confirmed-password)))
    (let ((the-encrypted-string
	   (encrypt the-file-string password)))
      (let ((new-name
	     (pathname-new-type
	      pathname
	      (let ((old-type (pathname-type pathname)))
		(if (not old-type)
		    "KY"
		    (string-append old-type ".KY"))))))
	(with-output-to-file new-name
	  (lambda ()
	    (write-string the-encrypted-string)))
	(delete-file pathname)
	(dired-redisplay new-name)))))

;;;; List Directory

(define-command list-directory
  "Display a list of files in or matching DIRNAME.
Prefix arg (second arg if noninteractive) means display a verbose listing.
Actions controlled by variables list-directory-brief-switches
 and list-directory-verbose-switches."
  (lambda ()
    (let ((argument (command-argument)))
      (list (prompt-for-directory (if argument
				      "List directory (verbose)"
				      "List directory (brief)")
				  false)
	    argument)))
  (lambda (directory argument)
    (let ((directory (->pathname directory))
	  (buffer (temporary-buffer "*Directory*")))
      (disable-group-undo! (buffer-group buffer))
      (let ((point (buffer-end buffer)))
	(insert-string "Directory " point)
	(insert-string (->namestring directory) point)
	(insert-newline point)
	(read-directory directory
			(if argument
			    (ref-variable list-directory-verbose-switches)
			    (ref-variable list-directory-brief-switches))
			point))
      (set-buffer-point! buffer (buffer-start buffer))
      (buffer-not-modified! buffer)
      (pop-up-buffer buffer false))))

;;;; Utilities

(define (dired-filename-start lstart)
  (let ((eol (line-end lstart 0)))
    (let ((m
	   (re-search-forward
	    "\\(Jan\\|Feb\\|Mar\\|Apr\\|May\\|Jun\\|Jul\\|Aug\\|Sep\\|Oct\\|Nov\\|Dec\\)[ ]+[0-9]+"
	    lstart
	    eol
	    false)))
      (and m
	   (re-match-forward " *[^ ]* *" m eol)))))

(define (dired-filename-region lstart)
  (let ((start (dired-filename-start lstart)))
    (and start
	 (make-region start (skip-chars-forward "^ \n" start)))))

(define (set-dired-point! mark)
  (set-current-point!
   (let ((lstart (line-start mark 0)))
     (or (dired-filename-start lstart)
	 lstart))))

(define (dired-current-pathname)
  (let ((lstart (line-start (current-point) 0)))
    (guarantee-dired-filename-line lstart)
    (dired-pathname lstart)))

(define (guarantee-dired-filename-line lstart)
  (if (not (dired-filename-start lstart))
      (editor-error "No file on this line")))

(define (dired-pathname lstart)
  (merge-pathnames
   (directory-pathname (dired-buffer-directory (current-buffer)))
   (region->string (dired-filename-region lstart))))

(define (dired-mark char n)
  (do ((i 0 (fix:+ i 1)))
      ((fix:= i n) unspecific)
    (let ((lstart (line-start (current-point) 0)))
      (guarantee-dired-filename-line lstart)
      (dired-mark-1 lstart char)
      (set-dired-point! (line-start lstart 1)))))

(define (dired-mark-backward char n)
  (do ((i 0 (fix:+ i 1)))
      ((fix:= i n) unspecific)
    (let ((lstart (line-start (current-point) -1 'ERROR)))
      (set-dired-point! lstart)
      (guarantee-dired-filename-line lstart)
      (dired-mark-1 lstart char))))

(define (dired-mark-1 lstart char)
  (with-read-only-defeated lstart
    (lambda ()
      (delete-right-char lstart)
      (insert-chars char 1 lstart))))

(define (dired-file-line? lstart)
  (and (dired-filename-start lstart)
       (not (re-match-forward ". d" lstart (mark+ lstart 3)))))

(define (for-each-file-line buffer procedure)
  (let ((point (mark-right-inserting-copy (buffer-start buffer))))
    (do () ((group-end? point))
      (if (dired-file-line? point)
	  (procedure point))
      (move-mark-to! point (line-start point 1)))))

(define (dired-redisplay pathname #!optional mark)
  (let ((lstart
	 (mark-right-inserting-copy
	  (line-start (if (or (default-object? mark) (not mark))
			  (current-point)
			  mark)
		      0))))
    (with-read-only-defeated lstart
      (lambda ()
	(delete-string lstart (line-start lstart 1))
	(add-dired-entry pathname)))
    (if (mark= lstart (line-start (current-point) 0))
	(set-dired-point! lstart))))

(define (dired-kill-files)
  (let ((filenames (dired-marked-files dired-flag-delete-char)))
    (if (not (null? filenames))
	(let ((buffer (temporary-buffer " *Deletions*")))
	  (write-strings-densely
	   (map (lambda (filename)
		  (file-namestring (car filename)))
		filenames)
	   (mark->output-port (buffer-point buffer))
	   (window-x-size (current-window)))
	  (set-buffer-point! buffer (buffer-start buffer))
	  (buffer-not-modified! buffer)
	  (set-buffer-read-only! buffer)
	  (if (with-selected-buffer buffer
		(lambda ()
		  (local-set-variable! truncate-partial-width-windows false)
		  (prompt-for-yes-or-no? "Delete these files")))
	      ;; Must delete the files in reverse order so that the
	      ;; non-permanent marks remain valid as lines are
	      ;; deleted.
	      (let loop ((filenames (reverse! filenames)) (failures '()))
		(cond ((not (null? filenames))
		       (loop (cdr filenames)
			     (if (dired-kill-file! (car filenames))
				 failures
				 (cons (file-namestring (caar filenames))
				       failures))))
		      ((not (null? failures))
		       (message "Deletions failed: " failures)))))
	  (kill-buffer buffer)))))

(define (dired-kill-file! filename)
  (let ((deleted?
	 (catch-file-errors (lambda () false)
			    (lambda () (delete-file (car filename)) true))))
    (if deleted?
	(with-read-only-defeated (cdr filename)
	  (lambda ()
	    (delete-string (cdr filename)
			   (line-start (cdr filename) 1)))))
    deleted?))

(define dired-flag-delete-char #\D)
(define dired-marker-char #\*)

(define (dired-marked-files #!optional mark marker-char)
  (let ((mark
	 (if (or (default-object? mark) (not mark))
	     (buffer-start (current-buffer))
	     mark))
	(marker-char
	 (if (or (default-object? marker-char) (not marker-char))
	     dired-marker-char
	     marker-char)))
    (let loop ((start (line-start mark 0)))
      (let ((continue
	     (lambda ()
	       (let ((next (line-start start 1 #f)))
		 (if next
		     (loop next)
		     '())))))
	(if (and (dired-filename-start start)
		 (char=? marker-char (mark-right-char start)))
	    (cons (cons (dired-pathname start) start)
		  (continue))
	    (continue))))))

(define (dired-next-files n #!optional mark)
  (let ((mark
	 (if (or (default-object? mark) (not mark))
	     (current-point)
	     mark)))
    (let loop ((start (line-start mark 0)) (n n))
      (if (<= n 0)
	  '()
	  (let ((continue
		 (lambda ()
		   (let ((next (line-start start 1 #f)))
		     (if next
			 (loop next (- n 1))
			 '())))))
	    (if (dired-filename-start start)
		(cons (cons (dired-pathname start) start)
		      (continue))
		(continue)))))))

(define (dired-this-file #!optional mark)
  (let ((mark
	 (if (or (default-object? mark) (not mark))
	     (current-point)
	     mark)))
    (let ((start (line-start mark 0)))
      (and (dired-filename-start start)
	   (cons (dired-pathname start) start)))))