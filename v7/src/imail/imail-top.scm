;;; -*-Scheme-*-
;;;
;;; $Id: imail-top.scm,v 1.57 2000/05/17 19:24:09 cph Exp $
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

(define-variable imail-kept-headers
  "A list of regular expressions matching header fields one wants to see.
Headers matching these regexps are shown in the given order,
 and other headers are hidden.
This variable overrides imail-ignored-headers;
 to use imail-ignored-headers, set imail-kept-headers to '()."
  (map (lambda (name) (string-append "^" name "$"))
       '("date" "from" "to" "cc" "subject"))
  (lambda (object) (list-of-type? object string?)))

(define-variable imail-ignored-headers
  "A regular expression matching header fields one would rather not see."
  (regexp-group "via" "mail-from" "origin" "status" "received"
		"[a-z-]*message-id" "summary-line" "errors-to")
  string-or-false?)

(define-variable imail-message-filter
  "If not #f, is a filter procedure for new headers in IMAIL.
The procedure is called with one argument, a list of headers,
 and is expected to return another list of headers.
 Each list element is a pair of two strings, the name and value."
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

(define-variable imail-primary-folder
  "URL for the primary folder that you read your mail from."
  #f
  string-or-false?)

(define-variable imail-default-imap-server
  "The hostname of an IMAP server to connect to if none is otherwise specified.
May contain an optional port suffix \":<port>\".
May be overridden by an explicit hostname in imail-primary-folder."
  "localhost"
  string?)

(define-variable imail-default-user-id
  "A user id to use when authenticating to a mail server.
#F means use the id of the user running Edwin.
May be overridden by an explicit user id in imail-primary-folder."
  #f
  string-or-false?)

(define-variable imail-default-imap-mailbox
  "The name of the default mailbox to connect to on an IMAP server,
if none is otherwise specified.
May be overridden by an explicit mailbox in imail-primary-folder."
  "inbox"
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
	(let ((folder
	       (open-folder
		(if url-string
		    (imail-parse-partial-url url-string)
		    (imail-default-url)))))
	  (select-buffer
	   (let ((buffer
		  (or (imail-folder->buffer folder #f)
		      (let ((buffer
			     (new-buffer
			      (url-presentation-name (folder-url folder)))))
			(associate-imail-with-buffer buffer folder #f)
			buffer))))
	     (select-message folder
			     (or (first-unseen-message folder)
				 (selected-message #f buffer))
			     #t)
	     buffer)))))))

(define (imail-authenticator host user-id receiver)
  (call-with-pass-phrase (string-append "Password for user " user-id
					" on host " host)
			 receiver))

(define (associate-imail-with-buffer buffer folder message)
  (without-interrupts
   (lambda ()
     (buffer-put! buffer 'IMAIL-FOLDER folder)
     (buffer-put! buffer 'IMAIL-MESSAGE message)
     (store-property! folder 'BUFFER buffer)
     (set-buffer-default-directory!
      buffer
      (if (file-folder? folder)
	  (directory-pathname (file-folder-pathname folder))
	  (user-homedir-pathname)))
     (add-event-receiver! (folder-modification-event folder)
       (lambda (folder)
	 (maybe-add-command-suffix! notice-folder-modifications folder))))))

(define (imail-folder->buffer folder error?)
  (or (let ((buffer (get-property folder 'BUFFER #f)))
	(and buffer
	     (if (buffer-alive? buffer)
		 buffer
		 (begin
		   (remove-property! folder 'BUFFER)
		   #f))))
      (and error? (error:bad-range-argument folder 'IMAIL-FOLDER->BUFFER))))

(define (notice-folder-modifications folder)
  (let ((buffer (imail-folder->buffer folder #f)))
    (if buffer
	(imail-update-mode-line! buffer))))

(define (imail-default-url)
  (let ((primary-folder (ref-variable imail-primary-folder)))
    (if primary-folder
	(imail-parse-partial-url primary-folder)
	(imail-default-imap-url))))

(define (imail-parse-partial-url string)
  (->url
   (let ((colon (string-find-next-char string #\:)))
     (if colon
	 string
	 (string-append "imap:" string)))))

(define (imail-default-imap-url)
  (call-with-values
      (lambda ()
	(let ((server (ref-variable imail-default-imap-server)))
	  (let ((colon (string-find-next-char server #\:)))
	    (if colon
		(values (string-head server colon)
			(or (string->number (string-tail server (+ colon 1)))
			    (error "Invalid port specification:" server)))
		(values server 143)))))
    (lambda (host port)
      (make-imap-url (or (ref-variable imail-default-user-id)
			 (current-user-name))
		     host
		     port
		     (ref-variable imail-default-imap-mailbox)))))

(define (imail-present-user-alert procedure)
  (call-with-output-to-temporary-buffer " *IMAP alert*"
					'(READ-ONLY SHRINK-WINDOW
						    FLUSH-ON-SPACE)
					procedure))

(define (imail-message-wrapper . arguments)
  (apply message-wrapper #f arguments))

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
\\[imail-save-folder]	Save the current folder.

\\[imail-quit]       Quit IMAIL: save, then switch to another buffer.

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
	  Normally only reduced headers are shown."
  (lambda (buffer)
    (buffer-put! buffer 'REVERT-BUFFER-METHOD imail-revert-buffer)
    (add-kill-buffer-hook buffer imail-kill-buffer)
    (local-set-variable! mode-line-modified "--- " buffer)
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

(define-key 'imail #\g		'imail-get-new-mail)
(define-key 'imail #\s		'imail-save-folder)

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

(define (imail-revert-buffer buffer dont-use-auto-save? dont-confirm?)
  dont-use-auto-save?
  (let ((folder (selected-folder #t buffer)))
    (if (let ((status (folder-sync-status folder)))
	  (case status
	    ((UNSYNCHRONIZED)
	     #t)
	    ((SYNCHRONIZED PERSISTENT-MODIFIED)
	     (or dont-confirm?
		 (prompt-for-yes-or-no? "Revert buffer from folder")))
	    ((FOLDER-MODIFIED)
	     (prompt-for-yes-or-no? "Discard your changes to folder"))
	    ((BOTH-MODIFIED)
	     (prompt-for-yes-or-no?
	      "Persistent copy of folder changed; discard your changes"))
	    ((PERSISTENT-DELETED)
	     (editor-error "Persistent copy of folder deleted."))
	    (else
	     (error "Unknown folder-sync status:" status))))
	(begin
	  (discard-folder-cache folder)
	  (select-message
	   folder
	   (or (selected-message #f buffer)
	       (first-unseen-message folder))
	   #t)))))

(define (imail-kill-buffer buffer)
  (let ((folder (selected-folder #f buffer)))
    (if folder
	(begin
	  (close-folder folder)
	  (unmemoize-folder (folder-url folder))))))

;;;; Navigation

(define-command imail-select-message
  "Show message number N (prefix argument), counting from start of folder."
  "p"
  (lambda (index)
    (let ((folder (selected-folder)))
      (if (not (<= 1 index (folder-length folder)))
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
      (for-each (lambda (flag)
		  (if (not (message-flag? flag))
		      (error "Invalid flag name:" flag)))
		flags)
      (move-relative n
		     (lambda (message)
		       (there-exists? flags
			 (lambda (flag)
			   (message-flagged? message flag))))
		     (string-append "message with flag"
				    (if (fix:= 1 (length flags)) "" "s")
				    " "
				    (decorated-string-append "" ", " ""
							     flags))))))

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
	       (msg (selected-message))
	       (winner #f))
	    (let ((next (step msg predicate)))
	      (cond ((not next)
		     (if winner (select-message (selected-folder) winner))
		     (message "No " direction " " noun))
		    ((= delta 1)
		     (select-message (selected-folder) next))
		    (else
		     (loop (- delta 1) next next)))))))))

(define (select-message folder selector #!optional force? full-headers?)
  (let ((buffer (imail-folder->buffer folder #t))
	(message
	 (let loop ((selector selector))
	   (cond ((message? selector)
		  (and (message-attached? selector folder)
		       selector
		       (loop (message-index selector))))
		 ((not selector)
		  (last-message selector))
		 ((and (exact-integer? selector)
		       (<= 0 selector)
		       (< selector (folder-length folder)))
		  (get-message folder selector))
		 (else
		  (error:wrong-type-argument selector "message selector"
					     'SELECT-MESSAGE)))))
	(full-headers? (if (default-object? full-headers?) #f full-headers?)))
    (if (or (if (default-object? force?) #f force?)
	    (not (eq? message (buffer-get buffer 'IMAIL-MESSAGE 'UNKNOWN))))
	(begin
	  (buffer-reset! buffer)
	  (associate-imail-with-buffer buffer folder message)
	  (let ((mark (mark-left-inserting-copy (buffer-start buffer))))
	    (if message
		(begin
		  (store-property! message 'FULL-HEADERS? full-headers?)
		  (insert-string
		   (header-fields->string
		    (if full-headers?
			(message-header-fields message)
			(maybe-reformat-headers message buffer)))
		   mark)
		  (insert-newline mark)
		  (insert-string (message-body message) mark)
		  (guarantee-newline mark))
		(insert-string "[This folder has no messages in it.]" mark))
	    (mark-temporary! mark))
	  (set-buffer-point! buffer (buffer-start buffer))
	  (set-buffer-major-mode! buffer (ref-mode-object imail))
	  (buffer-not-modified! buffer)))
    (if message
	(message-seen message))
    (imail-update-mode-line! buffer)))

(define (selected-message #!optional error? buffer)
  (or (let ((buffer
	     (if (or (default-object? buffer) (not buffer))
		 (selected-buffer)
		 buffer)))
	(let ((method (buffer-get buffer 'IMAIL-MESSAGE-METHOD #f)))
	  (if method
	      (method buffer)
	      (let ((message (buffer-get buffer 'IMAIL-MESSAGE 'UNKNOWN)))
		(if (eq? message 'UNKNOWN)
		    (error "IMAIL-MESSAGE property not bound:" buffer))
		(and message
		     (let ((folder (selected-folder #f buffer)))
		       (if (message-attached? message folder)
			   message
			   (let ((message
				  (let ((index
					 (and folder
					      (message-detached? message)
					      (message-index message))))
				    (and index
					 (< index (folder-length folder))
					 (get-message folder index)))))
			     (buffer-put! buffer 'IMAIL-MESSAGE message)
			     message))))))))
      (and (if (default-object? error?) #t error?)
	   (error "No selected IMAIL message."))))

(define (selected-folder #!optional error? buffer)
  (let ((buffer
	 (chase-imail-buffer
	  (if (or (default-object? buffer) (not buffer))
	      (selected-buffer)
	      buffer))))
    (let ((folder (buffer-get buffer 'IMAIL-FOLDER 'UNKNOWN)))
      (if (eq? 'UNKNOWN folder)
	  (error "IMAIL-FOLDER property not bound:" buffer))
      (or folder
	  (and (if (default-object? error?) #t error?)
	       (error:bad-range-argument buffer 'SELECTED-FOLDER))))))

(define (chase-imail-buffer buffer)
  (let ((buffer* (buffer-get buffer 'IMAIL-BUFFER-REDIRECT #f)))
    (if buffer*
	(chase-imail-buffer buffer*)
	buffer)))

(define (imail-update-mode-line! buffer)
  (local-set-variable! mode-line-process
		       (imail-mode-line-summary-string buffer)
		       buffer)
  (buffer-modeline-event! buffer 'PROCESS-STATUS))

(define (imail-mode-line-summary-string buffer)
  (let ((message (selected-message #f buffer)))
    (and message
	 (let ((folder (message-folder message))
	       (index (message-index message)))
	   (and folder
		(if index
		    (string-append
		     " "
		     (number->string (+ 1 index))
		     "/"
		     (number->string (folder-length folder))
		     (decorated-string-append
		      "," "" ""
		      (flags-delete "seen" (message-flags message))))
		    " 0/0"))))))

(define (maybe-reformat-headers message buffer)
  (let ((headers
	 (let ((headers (message-header-fields message)))
	   (cond ((ref-variable imail-kept-headers buffer)
		  => (lambda (regexps)
		       (append-map!
			(lambda (regexp)
			  (list-transform-positive headers
			    (lambda (header)
			      (re-string-match regexp
					       (header-field-name header)
					       #t))))
			regexps)))
		 ((ref-variable imail-ignored-headers buffer)
		  => (lambda (regexp)
		       (list-transform-negative headers
			 (lambda (header)
			   (re-string-match regexp
					    (header-field-name header)
					    #t)))))
		 (else headers))))
	(filter (ref-variable imail-message-filter buffer)))
    (if filter
	(map (lambda (n.v)
	       (make-header-field (car n.v) (cdr n.v)))
	     (filter (map (lambda (header)
			    (cons (header-field-name header)
				  (header-field-value header)))
			  headers)))
	headers)))

;;;; Message deletion

(define-command imail-delete-message
  "Delete this message and stay on it."
  ()
  (lambda ()
    (delete-message (selected-message))))

(define-command imail-delete-forward
  "Delete this message and move to next nondeleted one.
Deleted messages stay in the file until the \\[imail-expunge] command is given."
  ()
  (lambda ()
    ((ref-command imail-delete-message))
    ((ref-command imail-next-undeleted-message) 1)))

(define-command imail-delete-backward
  "Delete this message and move to previous nondeleted one.
Deleted messages stay in the file until the \\[imail-expunge] command is given."
  ()
  (lambda ()
    ((ref-command imail-delete-message))
    ((ref-command imail-next-undeleted-message) -1)))

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
		     (previous-message message message-undeleted?)
		     (next-message message)
		     (previous-message message))
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
	 (remove-duplicates (append standard-message-flags
				    (folder-flags (selected-folder)))
			    string=?)))
   'DEFAULT-TYPE 'INSERTED-DEFAULT
   'HISTORY 'IMAIL-READ-FLAG
   'REQUIRE-MATCH? require-match?))

;;;; Message I/O

(define-command imail-input
  "Append messages to this folder from a specified folder."
  "sInput from folder"
  (lambda (url-string)
    (let ((folder (selected-folder)))
      (let ((folder* (open-folder url-string))
	    (url (folder-url folder)))
	(let ((n (folder-length folder*)))
	  (do ((index 0 (+ index 1)))
	      ((= index n))
	    (append-message (get-message folder* index) url)))
	(close-folder folder*))
      (select-message folder
		      (or (selected-message #f)
			  (first-unseen-message folder))))))

(define-command imail-output
  "Append this message to a specified folder."
  "sOutput to folder"
  (lambda (url-string)
    (let ((message (selected-message)))
      (append-message message url-string)
      (message-filed message)
      (if (ref-variable imail-delete-after-output)
	  ((ref-command imail-delete-forward) #f)))))

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
		      (rfc822:addresses->string
		       (rfc822:string->addresses from))
		      ""))
		": "
		(message-subject message)
		"]")))
	   #f
	   (lambda (mail-buffer)
	     (insert-region (buffer-start buffer)
			    (buffer-end buffer)
			    (buffer-end mail-buffer))
	     (if (window-has-no-neighbors? (current-window))
		 (select-buffer mail-buffer)
		 (select-buffer-other-window mail-buffer))
	     (message-forwarded message)))))))

(define-command imail-resend
  "Resend current message to ADDRESSES.
ADDRESSES is a string consisting of several addresses separated by commas."
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
			  (message-answered message)
			  (select-buffer-other-window mail-buffer))))))

(define (imail-reply-headers message cc?)
  (let ((resent-reply-to
	 (get-last-header-field-value message "resent-reply-to" #f))
	(from (get-first-header-field-value message "from" #f)))
    `(("To"
       ,(rfc822:addresses->string
	 (rfc822:string->addresses
	  (or resent-reply-to
	      (get-all-header-field-values message "reply-to")
	      from))))
      ("CC"
       ,(and cc?
	     (let ((to
		    (if resent-reply-to
			(get-last-header-field-value message "resent-to" #f)
			(get-all-header-field-values message "to")))
		   (cc
		    (if resent-reply-to
			(get-last-header-field-value message "resent-cc" #f)
			(get-all-header-field-values message "cc"))))
	       (let ((cc
		      (if (and to cc)
			  (string-append to ", " cc)
			  (or to cc))))
		 (and cc
		      (let ((addresses
			     (imail-dont-reply-to
			      (rfc822:string->addresses cc))))
			(and (not (null? addresses))
			     (rfc822:addresses->string addresses))))))))
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
			(let ((subject
			       (get-last-header-field-value message
							    "resent-subject"
							    #f)))
			  (and subject
			       (strip-subject-re subject))))
		   (message-subject message))))
	  (if (ref-variable imail-reply-with-re)
	      (string-append "Re: " subject)
	      subject))))))

(define (imail-dont-reply-to addresses)
  (if (not (ref-variable imail-dont-reply-to-names))
      (set-variable!
       imail-dont-reply-to-names
       (string-append
	(let ((imail-default-dont-reply-to-names
	       (ref-variable imail-default-dont-reply-to-names)))
	  (if imail-default-dont-reply-to-names
	      (string-append imail-default-dont-reply-to-names "\\|")
	      ""))
	(re-quote-string (current-user-name))
	"\\>")))
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

(define (message-subject message)
  (let ((subject (get-first-header-field-value message "subject" #f)))
    (if subject
	(strip-subject-re subject)
	"")))

(define (strip-subject-re subject)
  (if (string-prefix-ci? "re:" subject)
      (strip-subject-re (string-trim-left (string-tail subject 3)))
      subject))

;;;; Miscellany

(define-command imail-quit
  "Quit out of IMAIL."
  ()
  (lambda ()
    (let ((folder (selected-folder)))
      (save-folder folder)
      (close-folder folder))
    ((ref-command bury-buffer))))

(define-command imail-get-new-mail
  "Probe the mail server for new mail.
Selects the first new message if any new mail.
Currently useful only for IMAP folders."
  ()
  (lambda ()
    (let ((folder (selected-folder)))
      (let ((count (folder-modification-count folder))
	    (last (last-message folder)))
	(probe-folder folder)
	(if (> (folder-modification-count folder) count)
	    (select-message
	     folder
	     (or (cond ((not last)
			(first-message folder))
		       ((message-attached? last folder)
			(next-message last))
		       ((message-index last)
			=> (lambda (index)
			     (let ((index (+ index 1)))
			       (if (< index (folder-length folder))
				   (get-message folder index)
				   (first-unseen-message folder)))))
		       (else (first-unseen-message folder)))
		 (selected-message #f)))
	    (message "(No changes to mail folder)"))))))

(define-command imail-save-folder
  "Save the currently selected IMAIL folder."
  ()
  (lambda ()
    (save-folder (selected-folder))))

(define-command imail-toggle-header
  "Show full message headers if pruned headers currently shown, or vice versa."
  ()
  (lambda ()
    (let ((message (selected-message)))
      (select-message (selected-folder)
		      message
		      #t
		      (not (get-property message 'FULL-HEADERS? #f))))))

(define-command imail-search
  "Show message containing next match for given string.
Negative argument means search in reverse."
  (lambda ()
    (let ((reverse? (< (command-argument-numeric-value (command-argument)) 0)))
      (list (prompt-for-string (string-append (if reverse? "Reverse " "")
					      "IMAIL search")
			       #f
			       'DEFAULT-TYPE 'INSERTED-DEFAULT
			       'HISTORY 'IMAIL-SEARCH
			       'HISTORY-INDEX 0)
	    reverse?)))
  (lambda (pattern reverse?)
    (let ((folder (selected-folder))
	  (msg
	   (string-append (if reverse? "Reverse " "")
			  "IMAIL search for " pattern "...")))
      (message msg)
      (let ((index
	     (let ((index (message-index (selected-message))))
	       (let loop
		   ((indexes
		     (let ((indexes (search-folder folder pattern)))
		       (if reverse?
			   (reverse indexes)
			   indexes))))
		 (and (pair? indexes)
		      (if (if reverse?
			      (< (car indexes) index)
			      (> (car indexes) index))
			  (car indexes)
			  (loop (cdr indexes))))))))
	(if index
	    (begin
	      (select-message folder index)
	      (message msg "done"))
	    (editor-failure "Search failed: " pattern))))))