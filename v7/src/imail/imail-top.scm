;;; -*-Scheme-*-
;;;
;;; $Id: imail-top.scm,v 1.10 2000/01/20 17:47:59 cph Exp $
;;;
;;; Copyright (c) 1999-2000 Massachusetts Institute of Technology
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

;;;; IMAIL mail reader: top level

;;; **** Redisplay issues: Many operations modify the modeline, e.g.
;;; changes to the flags list of a message.

;;; **** Not yet implemented: FOLDER-MODIFIED?.

(declare (usual-integrations))

(define-variable imail-dont-reply-to-names
  "A regular expression specifying names to prune in replying to messages.
#f means don't reply to yourself."
  #f
  string-or-false?)

(define-variable imail-default-dont-reply-to-names
  "A regular expression specifying part of the value of the default value of
the variable `imail-dont-reply-to-names', for when the user does not set
`imail-dont-reply-to-names' explicitly.  (The other part of the default
value is the user's name.)
It is useful to set this variable in the site customisation file."
  "info-"
  string?)

(define-variable imail-ignored-headers
  "A regular expression matching header fields one would rather not see."
  "^via:\\|^mail-from:\\|^origin:\\|^status:\\|^received:\\|^[a-z-]*message-id:\\|^summary-line:\\|^errors-to:"
  string-or-false?)

(define-variable imail-message-filter
  "If not #f, is a filter procedure for new headers in IMAIL.
Called with the start and end marks of the header as arguments."
  #f
  (lambda (object) (or (not object) (procedure? object))))

(define-variable imail-delete-after-output
  "True means automatically delete a message that is copied to a file."
  #f
  boolean?)

(define-variable imail-reply-with-re
  "True means prepend subject with Re: in replies."
  #f
  boolean?)

(define-variable imail-user-name
  "A user name to use when authenticating to a mail server.
#f means use the default user name."
  #f
  string-or-false?)

(define-variable imail-primary-folder
  "URL for the primary folder that you read your mail from."
  "rmail:RMAIL"
  string?)

(define-command imail
  "Read and edit incoming mail.
May be called with an IMAIL folder URL as argument;
 then performs IMAIL editing on that folder,
 but does not copy any new mail into the folder."
  (lambda ()
    (list (and (command-argument)
	       (prompt-for-string "Run IMAIL on folder" #f))))
  (lambda (url-string)
    (bind-authenticator imail-authenticator
      (lambda ()
	(let* ((url
		(->url (or url-string (ref-variable imail-primary-folder))))
	       (folder (open-folder url)))
	  (select-buffer
	   (or (imail-folder->buffer folder)
	       (let ((buffer (new-buffer (imail-url->buffer-name url))))
		 (associate-imail-folder-with-buffer folder buffer)
		 (select-message folder (first-unseen-message folder))
		 buffer))))))
    (if (not url-string)
	((ref-command imail-get-new-mail) #f))))

(define (imail-authenticator url)
  (let ((user-name
	 (or (ref-variable imail-user-name)
	     (current-user-name))))
    (values user-name
	    (call-with-pass-phrase
	     (string-append "Password for user "
			    user-name
			    " to access IMAIL folder "
			    (url->string url))
	     string-copy))))

(define (associate-imail-folder-with-buffer folder buffer)
  (buffer-put! buffer 'IMAIL-FOLDER folder)
  (folder-put! folder 'BUFFER buffer))

(define (imail-folder->buffer folder)
  (or (folder-get folder 'BUFFER #f)
      (error:bad-range-argument buffer 'IMAIL-FOLDER->BUFFER)))

(define (buffer->imail-folder buffer)
  (or (buffer-get buffer 'IMAIL-FOLDER #f)
      (error:bad-range-argument buffer 'BUFFER->IMAIL-FOLDER)))

(define (selected-folder)
  (buffer->imail-folder (selected-buffer)))

(define (imail-url->buffer-name url)
  (url-body url))

(define-command imail-get-new-mail
  "Get new mail from this folder's inbox."
  ()
  (lambda ()
    (let ((folder (selected-folder)))
      (maybe-revert-folder folder
	(lambda (folder)
	  (prompt-for-yes-or-no?
	   (string-append
	    "Persistent copy of folder has changed since last read.  "
	    (if (folder-modified? folder)
		"Discard your changes"
		"Re-read folder")))))
      (let ((n-new (poll-folder folder)))
	(cond ((not n-new)
	       (message "(This folder has no associated inbox.)"))
	      ((= 0 n-new)
	       (message "(No new mail has arrived.)"))
	      (else
	       (select-message folder (- (count-messages folder) n-new))
	       (event-distributor/invoke! (ref-variable imail-new-mail-hook))
	       (message n-new
			" new message"
			(if (= n-new 1) "" "s")
			" read")))))))

(define-variable imail-new-mail-hook
  "An event distributor that is invoked when IMAIL incorporates new mail."
  (make-event-distributor))

(define-major-mode imail read-only "IMAIL"
  "IMAIL mode is used by \\[imail] for editing IMAIL files.
All normal editing commands are turned off.
Instead, these commands are available:

.	Move point to front of this message (same as \\[beginning-of-buffer]).
SPC	Scroll to next screen of this message.
DEL	Scroll to previous screen of this message.
\\[imail-next-undeleted-message]	Move to next non-deleted message.
\\[imail-previous-undeleted-message]	Move to previous non-deleted message.
\\[imail-next-message]	Move to next message whether deleted or not.
\\[imail-previous-message]	Move to previous message whether deleted or not.
\\[imail-last-message]	Move to the last message in folder.
\\[imail-select-message]	Jump to message specified by numeric position in file.
\\[imail-search]	Search for string and show message it is found in.

\\[imail-delete-forward]	Delete this message, move to next nondeleted.
\\[imail-delete-backward]	Delete this message, move to previous nondeleted.
\\[imail-undelete-previous-message]	Undelete message.  Tries current message, then earlier messages
	until a deleted message is found.
\\[imail-expunge]	Expunge deleted messages.
\\[imail-synchronize]	Synchonize the folder with the server.
	For file folders, synchronizes with the file.

\\[imail-quit]       Quit IMAIL: save, then switch to another buffer.

\\[imail-get-new-mail]	Read any new mail from the associated inbox into this folder.

\\[imail-mail]	Mail a message (same as \\[mail-other-window]).
\\[imail-reply]	Reply to this message.  Like \\[imail-mail] but initializes some fields.
\\[imail-forward]	Forward this message to another user.
\\[imail-continue]	Continue composing outgoing message started before.

\\[imail-output]       Output this message to a specified folder (append it).
\\[imail-input]	Append messages from a specified folder.

\\[imail-add-flag]	Add flag to message.  It will be displayed in the mode line.
\\[imail-kill-flag]	Remove a flag from current message.
\\[imail-next-flagged-message]	Move to next message with specified flag
          (flag defaults to last one specified).
          Standard flags:
	    answered, deleted, edited, filed, forwarded, resent, seen.
          Any other flag is present only if you add it with `\\[imail-add-flag]'.
\\[imail-previous-flagged-message]   Move to previous message with specified flag.

\\[imail-summary]	Show headers buffer, with a one line summary of each message.
\\[imail-summary-by-flags]	Like \\[imail-summary] only just messages with particular flag(s) are summarized.
\\[imail-summary-by-recipients]   Like \\[imail-summary] only just messages with particular recipient(s) are summarized.

\\[imail-toggle-header]	Toggle between full headers and reduced headers.
	  Normally only reduced headers are shown.
\\[imail-edit-current-message]	Edit the current message.  C-c C-c to return to IMAIL."
  (lambda (buffer)
    (buffer-put! buffer 'REVERT-BUFFER-METHOD imail-revert-buffer)
    (set-buffer-read-only! buffer)
    (disable-group-undo! (buffer-group buffer))
    (event-distributor/invoke! (ref-variable imail-mode-hook buffer) buffer)))

(define-variable imail-mode-hook
  "An event distributor that is invoked when entering IMAIL mode."
  (make-event-distributor))

(define-key 'imail #\.		'beginning-of-buffer)
(define-key 'imail #\space	'scroll-up)
(define-key 'imail #\rubout	'scroll-down)
(define-key 'imail #\n		'imail-next-undeleted-message)
(define-key 'imail #\p		'imail-previous-undeleted-message)
(define-key 'imail #\m-n	'imail-next-message)
(define-key 'imail #\m-p	'imail-previous-message)
(define-key 'imail #\j		'imail-select-message)
(define-key 'imail #\>		'imail-last-message)

(define-key 'imail #\a		'imail-add-flag)
(define-key 'imail #\k		'imail-kill-flag)
(define-key 'imail #\c-m-n	'imail-next-flagged-message)
(define-key 'imail #\c-m-p	'imail-previous-flagged-message)

(define-key 'imail #\d		'imail-delete-forward)
(define-key 'imail #\c-d	'imail-delete-backward)
(define-key 'imail #\u		'imail-undelete-previous-message)
(define-key 'imail #\x		'imail-expunge)

(define-key 'imail #\s		'imail-synchronize)
(define-key 'imail #\g		'imail-get-new-mail)

(define-key 'imail #\c-m-h	'imail-summary)
(define-key 'imail #\c-m-l	'imail-summary-by-flags)
(define-key 'imail #\c-m-r	'imail-summary-by-recipients)

(define-key 'imail #\m		'imail-mail)
(define-key 'imail #\r		'imail-reply)
(define-key 'imail #\c		'imail-continue)
(define-key 'imail #\f		'imail-forward)

(define-key 'imail #\t		'imail-toggle-header)
(define-key 'imail #\m-s	'imail-search)
(define-key 'imail #\o		'imail-output)
(define-key 'imail #\i		'imail-input)
(define-key 'imail #\q		'imail-quit)
(define-key 'imail #\?		'describe-mode)
(define-key 'imail #\w		'imail-edit-current-message)

(define (imail-revert-buffer buffer dont-use-auto-save? dont-confirm?)
  dont-use-auto-save?
  (let ((folder (buffer->imail-folder buffer))
	(message (selected-message #f buffer)))
    (let ((index (and message (message-index message))))
      (maybe-revert-folder folder
	(lambda (folder)
	  (or dont-confirm?
	      (prompt-for-yes-or-no?
	       (string-append "Revert buffer from folder "
			      (url->string (folder-url folder)))))))
      (select-message
       folder
       (cond ((eq? folder (message-folder message)) message)
	     ((and (<= 0 index) (< index (count-messages folder))) index)
	     (else (first-unseen-message folder)))))))

(define-command imail-quit
  "Quit out of IMAIL."
  ()
  (lambda ()
    ((ref-command save-buffer) #f)
    ((ref-command bury-buffer))))

(define-command imail-synchronize
  "Synchronize the current folder with the master copy on the server.
Currently meaningless for file-based folders."
  ()
  (lambda ()
    (synchronize-folder (selected-folder))))

;;;; Navigation

(define-command imail-select-message
  "Show message number N (prefix argument), counting from start of folder."
  "p"
  (lambda (index)
    (let ((folder (selected-folder)))
      (if (not (<= 1 index (count-messages folder)))
	  (editor-error "Message index out of bounds:" index))
      (select-message folder (- index 1)))))

(define-command imail-last-message
  "Show last message in folder."
  ()
  (lambda ()
    (let ((folder (selected-folder)))
      (select-message folder (last-message folder)))))

(define-command imail-next-message
  "Show following message whether deleted or not.
With prefix argument N, moves forward N messages,
or backward if N is negative."
  "p"
  (lambda (delta)
    (move-relative delta (lambda (message) message #t) "message")))

(define-command imail-previous-message
  "Show previous message whether deleted or not.
With prefix argument N, moves backward N messages,
or forward if N is negative."
  "p"
  (lambda (delta)
    ((ref-command imail-next-message) (- delta))))

(define-command imail-next-undeleted-message
  "Show following non-deleted message.
With prefix argument N, moves forward N non-deleted messages,
or backward if N is negative."
  "p"
  (lambda (delta)
    (move-relative delta message-undeleted? "undeleted message")))

(define-command imail-previous-undeleted-message
  "Show previous non-deleted message.
With prefix argument N, moves backward N non-deleted messages,
or forward if N is negative."
  "p"
  (lambda (delta)
    ((ref-command imail-next-undeleted-message) (- delta))))

(define-command imail-next-flagged-message
  "Show next message with one of the flags FLAGS.
FLAGS should be a comma-separated list of flag names.
If FLAGS is empty, the last set of flags specified is used.
With prefix argument N moves forward N messages with these flags."
  (lambda ()
    (flagged-message-arguments "Move to next message with flags"))
  (lambda (n flags)
    (let ((flags (map string-trim (burst-string flags "," #f))))
      (if (null? flags)
	  (editor-error "No flags have been specified."))
      (move-relative n
		     (lambda (message)
		       (there-exists? flags
			 (lambda (flag)
			   (message-flagged? message flag))))
		     (string-append "message with flags " flags)))))

(define-command imail-previous-flagged-message
  "Show previous message with one of the flags FLAGS.
FLAGS should be a comma-separated list of flag names.
If FLAGS is empty, the last set of flags specified is used.
With prefix argument N moves backward N messages with these flags."
  (lambda ()
    (flagged-message-arguments "Move to previous message with flags"))
  (lambda (n flags)
    ((ref-command imail-next-flagged-message) (- n) flags)))

(define (flagged-message-arguments prompt)
  (list (command-argument)
	(prompt-for-string prompt
			   #f
			   'DEFAULT-TYPE 'INSERTED-DEFAULT
			   'HISTORY 'IMAIL-NEXT-FLAGGED-MESSAGE
			   'HISTORY-INDEX 0)))

(define (move-relative delta predicate noun)
  (if (not (= 0 delta))
      (call-with-values
	  (lambda ()
	    (if (< delta 0)
		(values (- delta) previous-message "previous")
		(values delta next-message "next")))
	(lambda (delta step direction)
	  (let loop
	      ((delta delta)
	       (message (selected-message))
	       (winner #f))
	    (let ((next (step message predicate)))
	      (cond ((not next)
		     (if winner (select-message (selected-folder) winner))
		     (message "No " direction " " noun))
		    ((= delta 1)
		     (select-message (selected-folder) next))
		    (else
		     (loop (- delta 1) next next)))))))))

(define (select-message folder selector #!optional force?)
  (let ((buffer (imail-folder->buffer folder))
	(message
	 (cond ((or (not selector) (message? selector))
		selector)
	       ((and (exact-integer? selector)
		     (<= 0 selector)
		     (< selector (count-messages folder)))
		(get-message folder selector))
	       (else
		(error:wrong-type-argument selector "message selector"
					   'SELECT-MESSAGE)))))
    (if (and (not (if (default-object? force?) #f force?))
	     (eq? message (buffer-get buffer 'IMAIL-MESSAGE #f)))
	(imail-update-mode-line! buffer)
	(begin
	  (buffer-reset! buffer)
	  (associate-imail-folder-with-buffer folder buffer)
	  (buffer-put! buffer 'IMAIL-MESSAGE message)
	  (let ((mark (mark-left-inserting-copy (buffer-start buffer))))
	    (if message
		(begin
		  (for-each (lambda (line)
			      (insert-string line mark)
			      (insert-newline mark))
			    (let ((displayed
				   (get-message-property
				    message
				    "displayed-header-fields"
				    '())))
			      (if (eq? '() displayed)
				  (header-fields message)
				  displayed)))
		  (insert-newline mark)
		  (insert-string (message-body message) mark))
		(insert-string "[This folder has no messages in it.]" mark))
	    (guarantee-newline mark)
	    (mark-temporary! mark))
	  (set-buffer-major-mode! buffer (ref-mode-object imail))))))

(define (selected-message #!optional error? buffer)
  (or (buffer-get (if (or (default-object? buffer) (not buffer))
		      (selected-buffer)
		      buffer)
		  'SELECTED-MESSAGE
		  #f)
      (and (if (default-object? error?) #t error?)
	   (error "No selected IMAIL message."))))

(define (imail-update-mode-line! buffer)
  (local-set-variable! mode-line-process
		       (imail-mode-line-summary-string buffer)
		       buffer)
  (buffer-modeline-event! buffer 'PROCESS-STATUS))

(define (imail-mode-line-summary-string buffer)
  (let ((message (selected-message #f buffer)))
    (and message
	 (let ((folder (message-folder message))
	       (index (message-index message))
	       (flags (message-flags message)))
	   (if (and folder index)
	       (let ((line
		      (string-append
		       " "
		       (number->string (+ 1 index))
		       "/"
		       (number->string (count-messages folder)))))
		 (if (pair? flags)
		     (string-append line "," (separated-append flags ","))
		     line))
	       " 0/0")))))

;;;; Message deletion

(define-command imail-delete-message
  "Delete this message and stay on it."
  ()
  (lambda ()
    (delete-message (selected-message))))

(define-command imail-delete-forward
  "Delete this message and move to next nondeleted one.
Deleted messages stay in the file until the \\[imail-expunge] command is given.
With prefix argument, delete and move backward."
  "P"
  (lambda (backward?)
    ((ref-command imail-delete-message))
    ((ref-command imail-next-undeleted-message) (if backward? -1 1))))

(define-command imail-delete-backward
  "Delete this message and move to previous nondeleted one.
Deleted messages stay in the file until the \\[imail-expunge] command is given."
  ()
  (lambda ()
    ((ref-command imail-delete-forward) #t)))

(define-command imail-undelete-previous-message
  "Back up to deleted message, select it, and undelete it."
  ()
  (lambda ()
    (let ((message (selected-message)))
      (if (message-deleted? message)
	  (undelete-message message)
	  (let ((message (previous-message message message-deleted?)))
	    (if (not message)
		(editor-error "No previous deleted message."))
	    (undelete-message message)
	    (select-message (message-folder message) message))))))

(define-command imail-expunge
  "Actually erase all deleted messages in the folder."
  ()
  (lambda ()
    (let ((folder (selected-folder))
	  (message
	   (let ((message (selected-message)))
	     (if (message-deleted? message)
		 (or (next-message message message-undeleted?)
		     (previous-message message message-undeleted?))
		 message))))
      (expunge-deleted-messages folder)
      (select-message folder message))))

;;;; Message flags

(define-command imail-add-flag
  "Add FLAG to flags associated with current IMAIL message.
Completion is performed over known flags when reading."
  (lambda ()
    (list (imail-read-flag "Add flag" #f)))
  (lambda (flag)
    (set-message-flag (selected-message) flag)))

(define-command imail-kill-flag
  "Remove FLAG from flags associated with current IMAIL message.
Completion is performed over known flags when reading."
  (lambda ()
    (list (imail-read-flag "Remove flag" #t)))
  (lambda (flag)
    (clear-message-flag (selected-message) flag)))

(define (imail-read-flag prompt require-match?)
  (prompt-for-string-table-name
   prompt #f
   (alist->string-table
    (map list
	 (append standard-message-flags
		 (folder-flags (selected-folder)))))
   'DEFAULT-TYPE 'INSERTED-DEFAULT
   'HISTORY 'IMAIL-READ-FLAG
   'HISTORY-INDEX 0
   'REQUIRE-MATCH? require-match?))

;;;; Message I/O

(define-command imail-input
  "Append messages to this folder from a specified folder."
  "sInput from IMAIL folder"
  (lambda (url-string)
    (let ((folder (selected-folder))
	  (message (selected-message))
	  (folder* (open-folder url-string)))
      (let ((n (count-messages folder*)))
	(do ((index 0 (+ index 1)))
	    ((= index n))
	  (append-message folder (get-message folder* index))))
      (if (not message)
	  (select-message folder (first-unseen-message folder))))))

(define-command imail-output
  "Append this message to a specified folder."
  "sOutput to IMAIL folder"
  (lambda (url-string)
    (let ((message (selected-message)))
      (append-message (open-folder url-string) message)
      (set-message-flag message "filed"))
    (if (ref-variable imail-delete-after-output)
	((ref-command imail-delete-forward) #f))))

;;;; Sending mail

(define-command imail-mail
  "Send mail in another window.
While composing the message, use \\[mail-yank-original] to yank the
original message into it."
  ()
  (lambda ()
    (make-mail-buffer '(("To" "") ("Subject" ""))
		      (selected-buffer)
		      select-buffer-other-window)))

(define-command imail-continue
  "Continue composing outgoing message previously being composed."
  ()
  (lambda ()
    ((ref-command mail-other-window) #t)))

(define-command imail-forward
  "Forward the current message to another user.
With prefix argument, \"resend\" the message instead of forwarding it;
see the documentation of `imail-resend'."
  "P"
  (lambda (resend?)
    (if resend?
	(dispatch-on-command (ref-command-object imail-resend))
	(let ((buffer (selected-buffer))
	      (message (selected-message)))
	  (make-mail-buffer
	   `(("To" "")
	     ("Subject"
	      ,(string-append
		"["
		(let ((from (get-first-header-field-value message "from" #f)))
		  (if from
		      (rfc822-addresses->string
		       (string->rfc822-addresses from))
		      ""))
		": "
		(or (get-first-header-field-value message "subject" #f) "")
		"]")))
	   #f
	   (lambda (mail-buffer)
	     (insert-region (buffer-start buffer)
			    (buffer-end buffer)
			    (buffer-end mail-buffer))
	     (if (window-has-no-neighbors? (current-window))
		 (select-buffer mail-buffer)
		 (select-buffer-other-window mail-buffer))
	     (set-message-flag message "forwarded")))))))

(define-command imail-resend
  "Resend current message to ADDRESSES.
ADDRESSES a string consisting of several addresses separated by commas."
  "sResend to"
  (lambda (addresses)
    ???))

(define-command imail-reply
  "Reply to the current message.
Normally include CC: to all other recipients of original message;
 prefix argument means ignore them.
While composing the reply, use \\[mail-yank-original] to yank the
 original message into it."
  "P"
  (lambda (just-sender?)
    (let ((buffer (selected-buffer))
	  (message (selected-message)))
      (make-mail-buffer (imail-reply-headers message (not just-sender?))
			buffer
			(lambda (mail-buffer)
			  (set-message-flag message "answered")
			  (select-buffer-other-window mail-buffer))))))

(define (imail-reply-headers message cc?)
  (let ((resent-reply-to
	 (get-last-header-field-value message "resent-reply-to" #f))
	(from (get-first-header-field-value message "from" #f)))
    `(("To"
       ,(rfc822-addresses->string
	 (string->rfc822-addresses
	  (or resent-reply-to
	      (get-all-header-field-values message "reply-to" #f)
	      from))))
      ("CC"
       ,(and cc?
	     (let ((to
		    (if resent-reply-to
			(get-last-header-field-value message "resent-to" #f)
			(get-all-header-field-values message "to" #f)))
		   (cc
		    (if resent-reply-to
			(get-last-header-field-value message "resent-cc" #f)
			(get-all-header-field-values message "cc" #f))))
	       (let ((cc
		      (if (and to cc)
			  (string-append to ", " cc)
			  (or to cc))))
		 (and cc
		      (let ((addresses
			     (imail-dont-reply-to
			      (string->rfc822-addresses cc))))
			(and (not (null? addresses))
			     (rfc822-addresses->string addresses))))))))
      ("In-reply-to"
       ,(if resent-reply-to
	    (make-in-reply-to-field
	     from
	     (get-last-header-field-value message "resent-date" #f)
	     (get-last-header-field-value message "resent-message-id" #f))
	    (make-in-reply-to-field
	     from
	     (get-first-header-field-value message "date" #f)
	     (get-first-header-field-value message "message-id" #f))))
      ("Subject"
       ,(let ((subject
	       (or (and resent-reply-to
			(get-last-header-field-value message
						     "resent-subject"
						     #f))
		   (get-first-header-field-value message "subject" #f))))
	  (cond ((not subject) "")
		((ref-variable imail-reply-with-re)
		 (if (string-prefix-ci? "re:" subject)
		     subject
		     (string-append "Re: " subject)))
		(else
		 (do ((subject
		       subject
		       (string-trim-left (string-tail subject 3))))
		     ((not (string-prefix-ci? "re:" subject))
		      subject)))))))))

(define (imail-dont-reply-to addresses)
  (let ((pattern
	 (re-compile-pattern
	  (string-append "\\(.*!\\|\\)\\("
			 (ref-variable imail-dont-reply-to-names)
			 "\\)")
	  #t)))
    (let loop ((addresses addresses))
      (if (pair? addresses)
	  (if (re-string-match pattern (car addresses))
	      (loop (cdr addresses))
	      (cons (car addresses) (loop (cdr addresses))))
	  '()))))

;;;; Message editing

(define-command imail-edit-current-message
  "Edit the current IMAIL message."
  ()
  (lambda ()
    ;; Guarantee that this buffer has both folder and message bindings.
    (selected-folder)
    (selected-message)
    (let ((buffer (selected-buffer)))
      (set-buffer-major-mode! buffer (ref-mode-object imail-edit))
      (set-buffer-writable! buffer)
      (message
       (substitute-command-keys
	"Editing: Type \\[imail-cease-edit] to return to Imail, \\[imail-abort-edit] to abort."
	buffer)))))

(define-major-mode imail-edit text "IMAIL Edit"
  "Major mode for editing the contents of an IMAIL message.
The editing commands are the same as in Text mode,
together with two commands to return to regular IMAIL:
  \\[imail-abort-edit] cancels the changes you have made and returns to IMAIL;
  \\[imail-cease-edit] makes them permanent."
  (lambda (buffer)
    (enable-group-undo! (buffer-group buffer))))

(define-key 'imail-edit '(#\c-c #\c-c)	'imail-cease-edit)
(define-key 'imail-edit '(#\c-c #\c-\])	'imail-abort-edit)

(define-command imail-cease-edit
  "Finish editing message; switch back to IMAIL proper."
  ()
  (lambda ()
    (call-with-values
	(lambda ()
	  (let ((buffer (selected-buffer)))
	    (set-buffer-writable! buffer)
	    (buffer-widen! buffer)
	    (guarantee-newline (buffer-end buffer))
	    (let ((body-start
		   (search-forward "\n\n"
				   (buffer-start buffer)
				   (buffer-end buffer)
				   #f)))
	      (if body-start
		  (values (extract-string (buffer-start buffer)
					  (mark-1+ body-start))
			  (extract-string body-start
					  (buffer-end buffer)))
		  (values (extract-string (buffer-start buffer)
					  (buffer-end buffer))
			  "")))))
      (lambda (headers-string body)
	(let ((message (selected-message)))
	  (set-header-fields! message (string->header-fields headers-string))
	  (set-message-body! message body)
	  (select-message (selected-folder) message #t))))))

(define-command imail-abort-edit
  "Abort edit of current message; restore original contents."
  ()
  (lambda ()
    (select-message (selected-folder) (selected-message) #t)))