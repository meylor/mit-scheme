;;; -*-Scheme-*-
;;;
;;;	$Header: /Users/cph/tmp/foo/mit-scheme/mit-scheme/v7/src/edwin/lincom.scm,v 1.108 1991/04/21 00:51:10 cph Exp $
;;;
;;;	Copyright (c) 1986, 1989-91 Massachusetts Institute of Technology
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

;;;; Line/Indentation Commands

(declare (usual-integrations))

;;;; Lines

(define-command count-lines-region
  "Type number of lines from point to mark."
  "r"
  (lambda (region)
    (message "Region has "
	     (write-to-string (region-count-lines region))
	     " lines")))

(define-command transpose-lines
  "Transpose the lines before and after the cursor.
With a positive argument it transposes the lines before and after the
cursor, moves right, and repeats the specified number of times,
dragging the line to the left of the cursor right.

With a negative argument, it transposes the two lines to the left of
the cursor, moves between them, and repeats the specified number of
times, exactly undoing the positive argument form.

With a zero argument, it transposes the lines at point and mark.

At the end of a buffer, with no argument, the preceding two lines are
transposed."
  "p"
  (lambda (argument)
    (cond ((and (= argument 1) (group-end? (current-point)))
	   (if (not (line-start? (current-point)))
	       (insert-newlines 1))
	   (insert-string (extract-and-delete-string
			   (forward-line (current-point) -2 'ERROR)
			   (forward-line (current-point) -1 'ERROR))
			  (current-point)))
	  (else
	   (transpose-things forward-line argument)))))

;;;; Pages

(define-command forward-page
  "Move forward to page boundary.  With arg, repeat, or go back if negative.
A page boundary is any string in Page Delimiters, at a line's beginning."
  "p"
  (lambda (argument)
    (set-current-point! (forward-page (current-point) argument 'BEEP))))

(define-command backward-page
  "Move backward to page boundary.  With arg, repeat, or go fwd if negative.
A page boundary is any string in Page Delimiters, at a line's beginning."
  "p"
  (lambda (argument)
    (set-current-point! (backward-page (current-point) argument 'BEEP))))

(define-command mark-page
  "Put mark at end of page, point at beginning."
  "P"
  (lambda (argument)
    (let ((end (forward-page (current-point) (1+ (or argument 0)) 'LIMIT)))
      (set-current-region! (make-region (backward-page end 1 'LIMIT) end)))))

(define-command narrow-to-page
  "Make text outside current page invisible."
  "d"
  (lambda (mark)
    (region-clip! (page-interior-region mark))))

(define (page-interior-region point)
  (if (and (group-end? point)
	   (mark= (re-match-forward (ref-variable page-delimiter)
				    (line-start point 0)
				    point)
		  point))
      (make-region point point)
      (let ((end (forward-page point 1 'LIMIT)))
	(make-region (backward-page end 1 'LIMIT)
		     (let ((end* (line-end end -1 'LIMIT)))
		       (if (mark< end* point)
			   end
			   end*))))))

(define-command count-lines-page
  "Report number of lines on current page."
  "d"
  (lambda (point)
    (let ((end
	   (let ((end (forward-page point 1 'LIMIT)))
	     (if (group-end? end) end (line-start end 0)))))
      (let ((start (backward-page end 1 'LIMIT)))
	(message "Page has " (count-lines-string start end)
		 " lines (" (count-lines-string start point)
		 " + " (count-lines-string point end) ")")))))

(define (count-lines-string start end)
  (write-to-string (region-count-lines (make-region start end))))

(define-command what-page
  "Report page and line number of point."
  ()
  (lambda ()
    (without-group-clipped! (buffer-group (current-buffer))
      (lambda ()
	(message "Page " (write-to-string (current-page))
		 ", Line " (write-to-string (current-line)))))))

(define (current-page)
  (region-count-pages (make-region (buffer-start (current-buffer))
				   (current-point))))

(define (current-line)
  (region-count-lines
   (make-region (backward-page (forward-page (current-point) 1 'LIMIT)
			       1 'LIMIT)
		(current-point))))

(define (region-count-pages region)
  (let ((end (region-end region)))
    (define (loop count start)
      (if (or (not start) (mark> start end))
	  count
	  (loop (1+ count) (forward-page start 1))))
    (loop 0 (region-start region))))

;;;; Indentation

(define (indent-to-left-margin)
  (maybe-change-indentation (ref-variable left-margin)
			    (line-start (current-point) 0)))

(define-variable indent-line-procedure
  "Procedure used to indent current line.
If this is the procedure indent-to-left-margin,
\\[indent-for-tab-command] will insert tab characters rather than indenting."
  indent-to-left-margin)

(define-command indent-according-to-mode
  "Indent line in proper way for current major mode.
The exact behavior of this command is determined
by the variable indent-line-procedure."
  ()
  (lambda ()
    ((ref-variable indent-line-procedure))))

(define-command indent-for-tab-command
  "Indent line in proper way for current major mode.
The exact behavior of this command is determined
by the variable indent-line-procedure."
  "p"
  (lambda (argument)
    (let ((indent-line-procedure (ref-variable indent-line-procedure)))
      (if (eq? indent-line-procedure indent-to-left-margin)
	  (insert-chars #\tab argument)
	  (indent-line-procedure)))))

(define-command newline-and-indent
  "Insert a newline, then indent according to major mode.
Indentation is done using the current indent-line-procedure,
except that if there is a fill-prefix it is used to indent.
In programming language modes, this is the same as TAB.
In some text modes, where TAB inserts a tab, this indents to the
specified left-margin column."
  ()
  (lambda ()
    (delete-horizontal-space)
    (insert-newlines 1)
    (let ((fill-prefix (ref-variable fill-prefix)))
      (if fill-prefix
	  (region-insert-string! (current-point) fill-prefix)
	  ((ref-command indent-according-to-mode))))))

(define-command reindent-then-newline-and-indent
  "Reindent the current line according to mode (like
\\[indent-according-to-mode]), then insert a newline,
and indent the new line indent according to mode."
  ()
  (lambda ()
    (delete-horizontal-space)
    ((ref-command indent-according-to-mode))
    ((ref-command newline) false)
    ((ref-command indent-according-to-mode))))

(define-variable indent-tabs-mode
  "If false, do not use tabs for indentation or horizontal spacing."
  true
  boolean?)

(define-command indent-tabs-mode
  "Enables or disables use of tabs as indentation.
A positive argument turns use of tabs on;
zero or negative, turns it off.
With no argument, the mode is toggled."
  "P"
  (lambda (argument)
    (set-variable! indent-tabs-mode
		   (if argument
		       (positive? argument)
		       (not (ref-variable indent-tabs-mode))))))

(define-command insert-tab
  "Insert a tab character."
  ()
  (lambda ()
    (if (ref-variable indent-tabs-mode)
	(insert-char #\tab)
	(maybe-change-column
	 (let ((tab-width (ref-variable tab-width)))
	   (* tab-width (1+ (quotient (current-column) tab-width))))))))

(define-command indent-relative
  "Space out to under next indent point in previous nonblank line.
An indent point is a non-whitespace character following whitespace."
  ()
  (lambda ()
    (let ((point (current-point)))
      (let ((indentation (indentation-of-previous-non-blank-line point)))
	(cond ((not (= indentation (current-indentation point)))
	       (change-indentation indentation point))
	      ((line-start? (horizontal-space-start point))
	       (set-current-point! (horizontal-space-end point))))))))

(define (indentation-of-previous-non-blank-line mark)
  (let ((start (find-previous-non-blank-line mark)))
    (if start
	(current-indentation start)
	0)))

(define-variable indent-region-procedure
  "Function which is short cut to indent each line in region with Tab.
#F means really call Tab on each line."
  false
  (lambda (object)
    (or (false? object)
	(and (procedure? object)
	     (procedure-arity-valid? object 2)))))

(define-command indent-region
  "Indent each nonblank line in the region.
With no argument, indent each line with Tab.
With argument COLUMN, indent each line to that column."
  "r\nP"
  (lambda (region argument)
    (let ((start (region-start region))
	  (end (region-end region)))
      (cond (argument
	     (indent-region start end argument))
	    ((ref-variable indent-region-procedure)
	     ((ref-variable indent-region-procedure) start end))
	    (else
	     (for-each-line-in-region start end
	       (let ((indent-line (ref-variable indent-line-procedure)))
		 (lambda (start)
		   (set-current-point! start)
		   (indent-line)))))))))

(define (indent-region start end n-columns)
  (if (exact-nonnegative-integer? n-columns)
      (for-each-line-in-region start end
	(lambda (start)
	  (delete-string start (horizontal-space-end start))
	  (insert-horizontal-space n-columns start)))))

(define-command indent-rigidly
  "Indent all lines starting in the region sideways by ARG columns."
  "r\nP"
  (lambda (region argument)
    (if argument
	(indent-rigidly (region-start region) (region-end region) argument))))

(define (indent-rigidly start end n-columns)
  (for-each-line-in-region start end
    (lambda (start)
      (let ((end (horizontal-space-end start)))
	(if (line-end? end)
	    (delete-string start end)
	    (let ((new-column (max 0 (+ n-columns (mark-column end)))))
	      (delete-string start end)
	      (insert-horizontal-space new-column start)))))))

(define (for-each-line-in-region start end procedure)
  (if (not (mark<= start end))
      (error "Marks incorrectly related:" start end))
  (let ((start (mark-right-inserting-copy (line-start start 0))))
    (let ((end
	   (mark-left-inserting-copy
	    (if (and (line-start? end) (mark< start end))
		(mark-1+ end)
		(line-end end 0)))))
      (let loop ()
	(procedure start)
	(let ((m (line-end start 0)))
	  (if (mark< m end)
	      (begin
		(move-mark-to! start (mark1+ m))
		(loop)))))
      (mark-temporary! start)
      (mark-temporary! end))))

(define-command newline
  "Insert newline, or move onto blank line.
A blank line is one containing only spaces and tabs
\(which are killed if we move onto it).  Single blank lines
\(followed by nonblank lines) are not eaten up this way.
An argument inhibits this."
  "P"
  (lambda (argument)
    (cond ((not argument)
	   (if (line-end? (current-point))
	       (let ((m1 (line-start (current-point) 1)))
		 (if (and m1
			  (line-blank? m1)
			  (let ((m2 (line-start m1 1)))
			    (and m2
				 (line-blank? m2))))
		     (begin
		       (set-current-point! m1)
		       (delete-horizontal-space))
		     (insert-newlines 1)))
	       (insert-newlines 1)))
	  (else
	   (insert-newlines argument)))))

(define-command split-line
  "Move rest of this line vertically down.
Inserts a newline, and then enough tabs/spaces so that
what had been the rest of the current line is indented as much as
it had been.  Point does not move, except to skip over indentation
that originally followed it. 
With argument, makes extra blank lines in between."
  "p"
  (lambda (argument)
    (set-current-point! (horizontal-space-end (current-point)))
    (let ((m* (mark-right-inserting (current-point))))
      (insert-newlines (max argument 1))
      (insert-horizontal-space (mark-column m*))
      (set-current-point! m*))))

(define-command back-to-indentation
  "Move to end of this line's indentation."
  ()
  (lambda ()
    (set-current-point!
     (horizontal-space-end (line-start (current-point) 0)))))

(define-command delete-horizontal-space
  "Delete all spaces and tabs around point."
  ()
  delete-horizontal-space)

(define-command just-one-space
  "Delete all spaces and tabs around point, leaving just one space."
  ()
  (lambda ()
    (delete-horizontal-space)
    (insert-chars #\Space 1)))

(define-command delete-blank-lines
  "Kill all blank lines around this line's end.
If done on a non-blank line, kills all spaces and tabs at the end of
it, and all following blank lines (Lines are blank if they contain
only spaces and tabs).
If done on a blank line, deletes all preceding blank lines as well."
  ()
  (lambda ()
    (region-delete!
     (let ((point (current-point)))
       (make-region (if (line-blank? point)
			(let loop ((m1 (line-start point 0)))
			  (let ((m2 (line-start m1 -1)))
			    (if (and m2 (line-blank? m2))
				(loop m2)
				m1)))
			(horizontal-space-start (line-end point 0)))
		    (line-end (let loop ((m1 point))
				(let ((m2 (line-start m1 1)))
				  (if (and m2 (line-blank? m2))
				      (loop m2)
				      m1)))
			      0))))))

(define-command delete-indentation
  "Kill newline and indentation at front of line.
Leaves one space in place of them.  With argument,
moves down one line first (killing newline after current line)."
  "P"
  (lambda (argument)
    (set-current-point!
     (horizontal-space-start
      (line-end (current-point) (if (not argument) -1 0) 'ERROR)))
    (let ((point (current-point)))
      (region-delete! (make-region point (line-start point 1 'ERROR)))
      (if (ref-variable fill-prefix)
	  (let ((match (match-forward (ref-variable fill-prefix))))
	    (if match (delete-string match))))
      (delete-horizontal-space)
      (if (or (line-start? point)
	      (line-end? point)
	      (not (or (char-set-member?
			(ref-variable delete-indentation-right-protected)
			(mark-left-char point))
		       (char-set-member?
			(ref-variable delete-indentation-left-protected)
			(mark-right-char point)))))
	  (insert-chars #\Space 1)))))

(define-variable delete-indentation-right-protected
  "\\[delete-indentation] won't insert a space to the right of these."
  (char-set #\( #\,))

(define-variable delete-indentation-left-protected
  "\\[delete-indentation] won't insert a space to the left of these."
  (char-set #\)))

;;;; Tabification

(define-command untabify
  "Convert all tabs in region to multiple spaces, preserving columns.
The variable tab-width controls the action."
  "r"
  (lambda (region)
    (untabify-region (region-start region) (region-end region))))

(define (untabify-region start end)
  (let ((start (mark-right-inserting-copy start))
	(end (mark-left-inserting-copy end)))
    (do ()
	((not (char-search-forward #\tab start end)))
      (let ((tab (re-match-start 0)))
	(move-mark-to! start (re-match-end 0))
	(let ((n-spaces (- (mark-column start) (mark-column tab))))
	  (delete-string tab start)
	  (insert-chars #\space n-spaces start))))
    (mark-temporary! start)
    (mark-temporary! end)))

(define-command tabify
  "Convert multiple spaces in region to tabs when possible.
A group of spaces is partially replaced by tabs
when this can be done without changing the column they end at.
The variable tab-width controls the action."
  "r"
  (lambda (region)
    (tabify-region (region-start region) (region-end region))))

(define (tabify-region start end)
  (let ((start (mark-left-inserting-copy start))
	(end (mark-left-inserting-copy end))
	(pattern (re-compile-pattern "[ \t][ \t]+" false))
	(tab-width (group-tab-width (mark-group start))))
    (do ()
	((not (re-search-buffer-forward pattern false false
					(mark-group start)
					(mark-index start)
					(mark-index end))))
      (move-mark-to! start (re-match-start 0))
      (let ((end-column (mark-column (re-match-end 0))))
	(delete-string start (re-match-end 0))
	(insert-horizontal-space end-column start tab-width)))
    (mark-temporary! start)
    (mark-temporary! end)))