#| -*-Scheme-*-

$Id: datime.scm,v 14.25 2000/03/22 17:44:39 cph Exp $

Copyright (c) 1988-2000 Massachusetts Institute of Technology

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
|#

;;;; Date and Time Routines
;;; package: (runtime date/time)

(declare (usual-integrations))

;;;; Decoded Time

;;; Based on Common Lisp definition.  Needs time zone stuff, and
;;; handling of abbreviated year specifications.

(define decoded-time-structure-tag "decoded-time")

(define-structure (decoded-time
		   (type vector)
		   (named decoded-time-structure-tag)
		   (conc-name decoded-time/)
		   (constructor %make-decoded-time)
		   (constructor allocate-decoded-time ())
		   (copier))
  (second #f read-only #t)
  (minute #f read-only #t)
  (hour #f read-only #t)
  (day #f read-only #t)
  (month #f read-only #t)
  (year #f read-only #t)
  (day-of-week #f)
  (daylight-savings-time #f read-only #t)
  (zone #f))

(define (make-decoded-time second minute hour day month year #!optional zone)
  (check-decoded-time-args second minute hour day month year
			   'MAKE-DECODED-TIME)
  (let ((zone (if (default-object? zone) #f zone)))
    (if (and zone (not (time-zone? zone)))
	(error:wrong-type-argument zone "time zone" 'MAKE-DECODED-TIME))
    (if zone
	(%make-decoded-time second minute hour day month year
			    (compute-day-of-week day month year)
			    0
			    zone)
	(let ((dt
	       (%make-decoded-time second minute hour day month year 0 -1 #f)))
	  ;; These calls fill in the other fields of the structure.
	  ;; ENCODE-TIME can easily signal an error, for example on
	  ;; unix machines when the time is prior to 1970.
	  (let ((t (ignore-errors
		    (lambda () ((ucode-primitive encode-time 1) dt)))))
	    (if (condition? t)
		(set-decoded-time/day-of-week!
		 dt
		 (compute-day-of-week day month year))
		((ucode-primitive decode-time 2) dt t)))
	  (if (decoded-time/zone dt)
	      (set-decoded-time/zone! dt (/ (decoded-time/zone dt) 3600)))
	  dt))))

(define (check-decoded-time-args second minute hour day month year procedure)
  (let ((check-type
	 (lambda (object)
	   (if (not (exact-nonnegative-integer? object))
	       (error:wrong-type-argument object
					  "exact non-negative integer"
					  procedure)))))
    (let ((check-range
	   (lambda (object min max)
	     (check-type object)
	     (if (not (<= min object max))
		 (error:bad-range-argument object procedure)))))
      (check-type year)
      (check-range month 1 12)
      (check-range day 1 (month/max-days month))
      (check-range hour 0 23)
      (check-range minute 0 59)
      (check-range second 0 59))))

(define (compute-day-of-week day month year)
  ;; This implements Zeller's Congruence.
  (modulo (+ day
	     (let ((y (remainder year 100)))
	       (+ y
		  (floor (/ y 4))))
	     (let ((c (quotient year 100)))
	       (- (floor (/ c 4))
		  (* 2 c)))
	     (let ((m (modulo (- month 2) 12)))
	       (- (floor (/ (- (* 13 m) 1) 5))
		  (* (floor (/ m 11))
		     (if (and (= 0 (remainder year 4))
			      (or (not (= 0 (remainder year 100)))
				  (= 0 (remainder year 400))))
			 2
			 1))))
	     ;; This -1 adjusts so that 0 corresponds to Monday.
	     ;; Normally, 0 corresponds to Sunday.
	     -1)
	  7))

(define (universal-time->local-decoded-time time)
  (let ((result (allocate-decoded-time)))
    ((ucode-primitive decode-time 2) result (- time epoch))
    (if (decoded-time/zone result)
	(set-decoded-time/zone! result (/ (decoded-time/zone result) 3600)))
    result))

(define (universal-time->global-decoded-time time)
  (let ((result (allocate-decoded-time)))
    ((ucode-primitive decode-utc 2) result (- time epoch))
    (if (decoded-time/zone result)
	(set-decoded-time/zone! result (/ (decoded-time/zone result) 3600)))
    result))

(define (decoded-time->universal-time dt)
  (+ ((ucode-primitive encode-time 1)
      (if (decoded-time/zone dt)
	  (let ((dt* (copy-decoded-time dt)))
	    (set-decoded-time/zone! dt* (* (decoded-time/zone dt*) 3600))
	    dt*)
	  dt))
     epoch))

(define (get-universal-time)
  (+ epoch ((ucode-primitive encoded-time 0))))

(define epoch 2208988800)

(define (local-decoded-time)
  (universal-time->local-decoded-time (get-universal-time)))

(define (global-decoded-time)
  (universal-time->global-decoded-time (get-universal-time)))

(define (time-zone? object)
  (and (number? object)
       (exact? object)
       (<= -24 object 24)
       (integer? (* 3600 object))))

(define (decoded-time/daylight-savings-time? dt)
  (> (decoded-time/daylight-savings-time dt) 0))

(define (decoded-time/date-string time)
  (string-append (let ((day (decoded-time/day-of-week time)))
		   (if day
		       (string-append (day-of-week/long-string day) " ")
		       ""))
		 (month/long-string (decoded-time/month time))
		 " "
		 (number->string (decoded-time/day time))
		 ", "
		 (number->string (decoded-time/year time))))

(define (decoded-time/time-string time)
  (let ((second (decoded-time/second time))
	(minute (decoded-time/minute time))
	(hour (decoded-time/hour time)))
    (string-append (number->string
		    (cond ((zero? hour) 12)
			  ((< hour 13) hour)
			  (else (- hour 12))))
		   (if (< minute 10) ":0" ":")
		   (number->string minute)
		   (if (< second 10) ":0" ":")
		   (number->string second)
		   " "
		   (if (< hour 12) "AM" "PM"))))

(define (universal-time->local-time-string time)
  (decoded-time->string (universal-time->local-decoded-time time)))

(define (universal-time->global-time-string time)
  (decoded-time->string (universal-time->global-decoded-time time)))

(define (file-time->local-time-string time)
  (decoded-time->string (file-time->local-decoded-time time)))

(define (file-time->global-time-string time)
  (decoded-time->string (file-time->global-decoded-time time)))

(define (decoded-time->string dt)
  ;; The returned string is in the format specified by RFC 822,
  ;; "Standard for the Format of ARPA Internet Text Messages",
  ;; provided that time-zone information is available from the C
  ;; library.
  (let ((d2 (lambda (n) (string-pad-left (number->string n) 2 #\0))))
    (string-append (let ((day (decoded-time/day-of-week dt)))
		     (if day
			 (string-append (day-of-week/short-string day) ", ")
			 ""))
		   (number->string (decoded-time/day dt))
		   " "
		   (month/short-string (decoded-time/month dt))
		   " "
		   (number->string (decoded-time/year dt))
		   " "
		   (d2 (decoded-time/hour dt))
		   ":"
		   (d2 (decoded-time/minute dt))
		   ":"
		   (d2 (decoded-time/second dt))
		   (let ((zone (decoded-time/zone dt)))
		     (if zone
			 (string-append
			  " "
			  (time-zone->string
			   (if (decoded-time/daylight-savings-time? dt)
			       (- zone 1)
			       zone)))
			 "")))))

(define (string->decoded-time string)
  ;; STRING must be in RFC-822 format.
  (let ((lose
	 (lambda ()
	   (error "Ill-formed RFC-822 time string:" string))))
    (let ((tokens
	   (let ((tokens (burst-string string #\space #t)))
	     (case (length tokens)
	       ((5) tokens)
	       ((6)
		(if (and (fix:= 4 (string-length (car tokens)))
			 (char=? #\, (string-ref (car tokens) 3))
			 (string-ci->index days-of-week/short-strings
					   (substring (car tokens) 0 3)))
		    (cdr tokens)
		    (lose)))
	       (else (lose))))))
      (let ((time (burst-string (list-ref tokens 3) #\: #f)))
	(if (not (fix:= 3 (length time)))
	    (error "Ill-formed RFC-822 time string:" string))
	(make-decoded-time (string->number (caddr time))
			   (string->number (cadr time))
			   (string->number (car time))
			   (string->number (list-ref tokens 0))
			   (string->month (list-ref tokens 1))
			   (let ((n (string->number (list-ref tokens 2))))
			     (and (exact-nonnegative-integer? n)
				  (if (< n 100)
				      (+ 1900 n)
				      n)))
			   (string->time-zone (list-ref tokens 4)))))))

(define (string->universal-time string)
  (decoded-time->universal-time (string->decoded-time string)))

(define (string->file-time string)
  (decoded-time->file-time (string->decoded-time string)))

(define (time-zone->string tz)
  (if (not (time-zone? tz))
      (error:wrong-type-argument tz "time zone" 'TIME-ZONE->STRING))
  (let ((minutes (round (* 60 (- tz)))))
    (let ((qr (integer-divide (abs minutes) 60))
	  (d2 (lambda (n) (string-pad-left (number->string n) 2 #\0))))
      (string-append (if (< minutes 0) "-" "+")
		     (d2 (integer-divide-quotient qr))
		     (d2 (integer-divide-remainder qr))))))

(define (string->time-zone string)
  (let ((entry
	 (list-search-positive named-time-zones
	   (lambda (zone)
	     (string-ci=? string (car zone))))))
    (if entry
	(cadr entry)
	(let ((n (string->number string)))
	  (if (not (and (exact-integer? n)
			(<= -2400 n 2400)))
	      (error "Malformed time zone:" string))
	  (let ((qr (integer-divide (abs n) 100)))
	    (let ((hours (integer-divide-quotient qr))
		  (minutes (integer-divide-remainder qr)))
	      (if (not (<= 0 minutes 59))
		  (error "Malformed time zone:" string))
	      (let ((hours (+ hours (/ minutes 60))))
		(if (< n 0)
		    hours
		    (- hours)))))))))

(define named-time-zones
  '(("UT" 0)
    ("GMT" 0)
    ("EST" 5) ("EDT" 4) ("CST" 6) ("CDT" 5)
    ("MST" 7) ("MDT" 6) ("PST" 8) ("PDT" 7)
    ("A" 1) ("B" 2) ("C" 3) ("D" 4) ("E" 5) ("F" 6)
    ("G" 7) ("H" 8) ("I" 9) ("K" 10) ("L" 11) ("M" 12)
    ("N" -1) ("O" -2) ("P" -3) ("Q" -4) ("R" -5) ("S" -6)
    ("T" -7) ("U" -8) ("V" -9) ("W" -10) ("X" -11) ("Y" -12)
    ("Z" 0)))

;;;; ISO C ctime() strings

(define (decoded-time->ctime-string dt)
  (string-append
   (day-of-week/short-string (decoded-time/day-of-week dt))
   " "
   (month/short-string (decoded-time/month dt))
   " "
   (string-pad-left (number->string (decoded-time/day dt)) 2)
   " "
   (string-pad-left (number->string (decoded-time/hour dt)) 2 #\0)
   ":"
   (string-pad-left (number->string (decoded-time/minute dt)) 2 #\0)
   ":"
   (string-pad-left (number->string (decoded-time/second dt)) 2 #\0)
   " "
   (number->string (decoded-time/year dt))))

(define (ctime-string->decoded-time string)
  (let ((lose (lambda () (error "Ill-formed ctime() string:" string))))
    (let ((tokens (burst-string string #\space #t)))
      (if (not (fix:= 5 (length tokens)))
	  (lose))
      (let ((time (burst-string (list-ref tokens 3) #\: #f)))
	(if (not (fix:= 3 (length time)))
	    (lose))
	(make-decoded-time (string->number (caddr time))
			   (string->number (cadr time))
			   (string->number (car time))
			   (string->number (list-ref tokens 2))
			   (string->month (list-ref tokens 1))
			   (let ((n (string->number (list-ref tokens 4))))
			     (if (not (exact-nonnegative-integer? n))
				 (lose))
			     (if (< n 100)
				 (+ 1900 n)
				 n)))))))

(define (universal-time->local-ctime-string time)
  (decoded-time->ctime-string (universal-time->local-decoded-time time)))

(define (universal-time->global-ctime-string time)
  (decoded-time->ctime-string (universal-time->global-decoded-time time)))

(define (ctime-string->universal-time string)
  (decoded-time->universal-time (ctime-string->decoded-time string)))

(define (file-time->local-ctime-string time)
  (decoded-time->ctime-string (file-time->local-decoded-time time)))

(define (file-time->global-ctime-string time)
  (decoded-time->ctime-string (file-time->global-decoded-time time)))

(define (ctime-string->file-time string)
  (decoded-time->file-time (ctime-string->decoded-time string)))

(define (month/max-days month)
  (guarantee-month month 'MONTH/MAX-DAYS)
  (vector-ref '#(31 29 31 30 31 30 31 31 30 31 30 31) (- month 1)))

(define (month/short-string month)
  (guarantee-month month 'MONTH/SHORT-STRING)
  (vector-ref month/short-strings (- month 1)))

(define (month/long-string month)
  (guarantee-month month 'MONTH/LONG-STRING)
  (vector-ref month/long-strings (- month 1)))

(define (guarantee-month month name)
  (if (not (exact-integer? month))
      (error:wrong-type-argument month "month integer" name))
  (if (not (<= 1 month 12))
      (error:bad-range-argument month name)))

(define (string->month string)
  (fix:+ 1
	 (or (string-ci->index month/short-strings string)
	     (string-ci->index month/long-strings string)
	     (error "Unknown month designation:" string))))

(define month/short-strings
  '#("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))

(define month/long-strings
  '#("January" "February" "March" "April" "May" "June" "July" "August"
	       "September" "October" "November" "December"))

(define (day-of-week/short-string day)
  (guarantee-day-of-week day 'DAY-OF-WEEK/SHORT-STRING)
  (vector-ref days-of-week/short-strings day))

(define (day-of-week/long-string day)
  (guarantee-day-of-week day 'DAY-OF-WEEK/LONG-STRING)
  (vector-ref days-of-week/long-strings day))

(define (guarantee-day-of-week day name)
  (if (not (exact-integer? day))
      (error:wrong-type-argument day "day-of-week integer" name))
  (if (not (<= 0 day 6))
      (error:bad-range-argument day name)))

(define (string->day-of-week string)
  (or (string-ci->index days-of-week/short-strings string)
      (string-ci->index days-of-week/long-strings string)
      (error "Unknown day-of-week designation:" string)))

(define days-of-week/short-strings
  '#("Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun"))

(define days-of-week/long-strings
  '#("Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday" "Sunday"))

(define (string-ci->index string-vector string)
  (let ((end (vector-length string-vector)))
    (let loop ((index 0))
      (cond ((fix:= index end) #f)
	    ((string-ci=? string (vector-ref string-vector index)) index)
	    (else (loop (fix:+ index 1)))))))

;; Upwards compatibility
(define decode-universal-time universal-time->local-decoded-time)
(define encode-universal-time decoded-time->universal-time)
(define get-decoded-time local-decoded-time)
(define universal-time->string universal-time->local-time-string)
(define file-time->string file-time->local-time-string)