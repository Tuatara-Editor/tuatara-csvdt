;;;; test.lisp --- The csvdt package: arguments, the lines given to csvdt, and runs of a real csvdt.
;;;; Copyright (C) 2025-2026 Michael A Jones.  GPL-3.0-or-later; see LICENSE.
;;;;
;;;; The runs need a csvdt: $CSVDT, else the one on the PATH; without one,
;;;; they are skipped.

(in-package #:tuatara.tests)

(define-test csvdt
  :description "The csvdt package: command lines split as a shell splits them, options read from csvdt itself,
the lines of a selection told to csvdt, and csvdt run over a buffer, a selection and banked lines.")

(defparameter *csvdt-test-program*
  (or (uiop:getenv "CSVDT") (tuatara.io:find-program "csvdt"))
  "The csvdt the tests run, or NIL when there is none.")

(defparameter *csvdt-test-source*
  (merge-pathnames "csvdt.lisp" (or *load-truename* *default-pathname-defaults*))
  "The package's source, beside these tests.")

(defmacro with-csvdt (() &body body)
  "Run BODY with *CSVDT-PROGRAM* the csvdt the tests run, or skip it without one."
  `(if (null *csvdt-test-program*)
       (skip "No csvdt to run: set CSVDT or put csvdt on the PATH" (true nil))
       (let ((csvdt::*csvdt-program* *csvdt-test-program*)
             (csvdt::*csvdt-options-cache* nil)
             (csvdt::*csvdt-history* '()))
         ,@body)))

(defun csvdt-test-rope (text)
  "TEXT as a rope."
  (tuatara.text:string->rope text))

(define-test (csvdt csvdt-split-arguments)
  (flet ((split (line) (csvdt::csvdt-split-arguments line)))
    ;; a comma stays inside its argument
    (is equal '("-H" "-p" "-a" "1,0" "-i" "0,replace") (split "-H -p -a 1,0 -i 0,replace"))
    (is equal '("-o0,+02:00") (split "-o0,+02:00"))
    ;; either quote, each holding what the other cannot
    (is equal '("--print-delimiter" " ") (split "--print-delimiter \" \""))
    (is equal '("--comment" "#") (split "--comment '#'"))
    (is equal '("--print-delimiter" "'") (split "--print-delimiter \"'\""))
    (is equal '("--print-delimiter" "\"") (split "--print-delimiter '\"'"))
    ;; the shell's escapes in double quotes, none in single ones
    (is equal (list (string #\Tab)) (split "\"\\t\""))
    (is equal '("C:\\data") (split "'C:\\data'"))
    (fail (split "\"C:\\data\""))
    ;; a backslash outside quotes is itself
    (is equal '("C:\\Users\\x") (split "C:\\Users\\x"))
    ;; every space a shell splits on, a pasted newline too
    (is equal '("-H" "--arr") (split (format nil "-H~%--arr~%")))
    (fail (split "-H \"open"))))

(define-test (csvdt csvdt-option-lists)
  (let ((records (csvdt::csvdt-parse-option-list
                  (format nil
                          "# csvdt-option-list 1~%# short	long	value	separator	value-name~%-H	--has-header	none	none	~%-f	--flexible	optional	equals	keep~%"))))
    (is = 2 (length records))
    (is equal "--flexible" (getf (second records) :long))
    (is equal "equals" (getf (second records) :separator)))
  ;; a format not known, or no list at all: declined, for --help to be read instead
  (false (csvdt::csvdt-parse-option-list (format nil "# csvdt-option-list 2~%-H	--has-header	none	none~%")))
  (false (csvdt::csvdt-parse-option-list ""))
  ;; the --help fallback: options at the start of a line, the first of each
  (let ((records (csvdt::csvdt-parse-help
                  (format nil
                          "Options:~%  -H, --has-header  first row~%      --trim <T>  how~%      --trim again in prose~%"))))
    (is equal '("--has-header" "--trim") (mapcar (lambda (r) (getf r :long)) records))
    (is equal "-H" (getf (first records) :short))
    (false (getf (first records) :value))))

(define-test (csvdt csvdt-lines-told-to-csvdt)
  ;; part of a line takes the whole line; an end at a line's start stops there
  (let ((rope (csvdt-test-rope (format nil "ab,c~%de,f~%gh,i~%"))))
    (is equal (cons 0 10) (csvdt::csvdt-whole-lines rope 2 7))
    (is equal (cons 5 10) (csvdt::csvdt-whole-lines rope 5 10))
    ;; ranges are made one list in order, those that touch one, and kept inside what csvdt is given
    (is equal '((0 . 10)) (csvdt::csvdt-settle rope '(0 . 15) '((5 . 10) (0 . 5))))
    (is equal '((5 . 10)) (csvdt::csvdt-settle rope '(5 . 10) '((0 . 15))))
    (is equal '(nil t) (multiple-value-list (csvdt::csvdt-settle rope '(5 . 10) '((0 . 4)))))
    ;; the lines, counted from 1 at the start of the input
    (is string= "1-2" (csvdt::csvdt-lines-argument rope 0 '((0 . 10))))
    (is string= "2" (csvdt::csvdt-lines-argument rope 0 '((5 . 10))))
    (is string= "1,3" (csvdt::csvdt-lines-argument rope 0 '((0 . 5) (10 . 15))))
    ;; a narrowing starting at the second line makes it line 1
    (is string= "1,2" (csvdt::csvdt-lines-argument rope 5 '((5 . 10) (10 . 15))))
    (is string= "2" (csvdt::csvdt-lines-argument rope 5 '((10 . 15)))))
  ;; a last line with no newline is a line
  (is string= "2" (csvdt::csvdt-lines-argument (csvdt-test-rope (format nil "a~%b")) 0 '((2 . 3)))))

(define-test (csvdt csvdt-narrowing-cuts-lines)
  (let ((rope (csvdt-test-rope (format nil "ab,c~%de,f~%gh,i~%"))))
    (is eq nil (csvdt::csvdt-cut-note rope '(5 . 10) '((5 . 10))))
    (true (search "first line" (csvdt::csvdt-cut-note rope '(7 . 10) '((7 . 10)))))
    (true (search "last line" (csvdt::csvdt-cut-note rope '(5 . 8) '((5 . 8)))))
    (true (search "first and last" (csvdt::csvdt-cut-note rope '(7 . 8) '((7 . 8)))))
    ;; the end matters only when the ranges reach it
    (is eq nil (csvdt::csvdt-cut-note rope '(5 . 8) '((5 . 6))))))

(define-test (csvdt csvdt-run-arguments)
  ;; --lines goes before the arguments, naming the lines counted from the start of the input
  (let ((rope (csvdt-test-rope (format nil "ab~%cd~%"))))
    (is equal '("--lines" "2" "-H") (csvdt::csvdt-run-arguments
                                     (csvdt::make-csvdt-job :rope rope :input '(0 . 6) :ranges '((3 . 6))
                                                            :arguments '("-H"))))
    (is equal '("-H") (csvdt::csvdt-run-arguments
                       (csvdt::make-csvdt-job :rope rope :input '(0 . 6) :arguments '("-H"))))))

(define-test (csvdt csvdt-widening-note)
  (multiple-value-bind (lines said)
      (csvdt::csvdt-widening-note (format nil "csvdt: '--lines' widened to whole records, taking lines 2-3~%other"))
    (is string= "2-3" lines)
    (is string= "other" said))
  (is equal '(nil "csvdt: bad") (multiple-value-list (csvdt::csvdt-widening-note "csvdt: bad"))))

(define-test (csvdt csvdt-version-needed)
  ;; asked once for a program found, however many runs follow; older than 1.2.0 is refused in words
  (with-test-directory (dir)
    (let* ((log (namestring (merge-pathnames "asked" dir)))
           (program (namestring (merge-pathnames "csvdt" dir))))
      (flet ((fake (version)
               (with-open-file (o program :direction :output :if-exists :supersede)
                 (format o "#!/bin/sh~%case \"$1\" in~%--version) echo x >> ~a; echo '~a';;~%~
                            *) printf '# csvdt-option-list 1\\n-H\\t--has-header\\t\\t\\n';;~%esac~%" log version))
               (sb-posix:chmod program #o755)))
        (let ((csvdt::*csvdt-program* program))
          (dolist (version '("csvdt 1.1.9+2026.10.abc (IANA tzdata 2026f)" "csvdt 0.9.0"))
            (setf csvdt::*csvdt-options-cache* nil)
            (fake version)
            (true (search "needs csvdt 1.2.0 or later"
                          (handler-case (progn (csvdt::csvdt-check-version) "")
                            (error (e) (princ-to-string e))))))
          (dolist (version '("csvdt 1.2.0+2026.11.e29952d (IANA tzdata 2026f)" "csvdt 1.10.0" "csvdt 2.0.1"))
            (setf csvdt::*csvdt-options-cache* nil)
            (fake version)
            (finish (csvdt::csvdt-check-version)))
          (setf csvdt::*csvdt-options-cache* nil)
          (delete-file log)
          (dotimes (i 3) (csvdt::csvdt-check-version))
          (is = 1 (length (uiop:read-file-lines log))))))))

(define-test (csvdt csvdt-option-names)
  (with-csvdt ()
    ;; the one option this package names is one csvdt reports
    (let ((reported (csvdt::csvdt-options)))
      (true (member "--lines" reported :test #'string=) "--lines is not an option csvdt reports")
      ;; an option whose value must be joined with = is offered with it
      (true (member "--flexible=" reported :test #'string=)))))

(define-test (csvdt csvdt-names-no-other-option)
  ;; options are csvdt's to report: none but --lines is named in the package
  (with-csvdt ()
    (let* ((source (alexandria:read-file-into-string *csvdt-test-source*))
           (allowed '("--list-options" "--help" "--version" "--lines")))
      (dolist (option (csvdt::csvdt-options))
        (let ((option (string-right-trim "=" option)))
          (unless (or (member option allowed :test #'string=) (< (length option) 3))
            (false (cl-ppcre:scan (format nil "[^A-Za-z0-9-]~a[^A-Za-z0-9-]" (cl-ppcre:quote-meta-chars option)) source)
                   "~a is named in csvdt.lisp" option)))))))

(defparameter *csvdt-test-text*
  (format nil "ts,x~%2026-07-25T12:00:00+02:00,a~%2026-07-26T12:00:00+02:00,b~%2026-07-27T12:00:00+02:00,c~%")
  "A buffer with a header and a timestamp: without a conversion, -H -p and no
arguments at all would give the same output.")

(defparameter *csvdt-test-utc*
  (format nil "to_utc,x~%2026-07-25T10:00:00+00:00,a~%2026-07-26T10:00:00+00:00,b~%2026-07-27T10:00:00+00:00,c~%")
  "*CSVDT-TEST-TEXT* with its timestamps put in UTC, as -H -p -u0 -i 0,replace gives it.")

(defun csvdt-test-output ()
  "The text of *csvdt output*, once the runs started have ended and been taken in."
  (loop while (find-if #'tuatara.runtime:job-running-p tuatara.runtime:*jobs*) do (sleep 0.01))
  (let ((out (tuatara.buffer:find-buffer "*csvdt output*")))
    (and out (tuatara.buffer:buffer-string out))))

(defun csvdt-test-forget-output ()
  "Kill *csvdt output*, so that a run is seen to make it."
  (let ((old (tuatara.buffer:find-buffer "*csvdt output*")))
    (when old (tuatara.buffer:kill-buffer old))))

(defun csvdt-test-run (keys &rest options)
  "Run KEYS in a session (RUN-KEYS-IN-TURNS takes OPTIONS), *csvdt output*
killed first; the frontend, the editor and the output."
  (csvdt-test-forget-output)
  (multiple-value-bind (f editor) (apply #'run-keys-in-turns (list keys) :text *csvdt-test-text* options)
    (values f editor (csvdt-test-output))))

(define-test (csvdt csvdt-run-buffer)
  (with-csvdt ()
    ;; the arguments offered, selected, typed over
    (multiple-value-bind (f editor out)
        (csvdt-test-run "M-x c s v d t - r u n - b u f f e r RET - H SPC - p SPC - u 0 SPC - i SPC 0 , r e p l a c e RET")
      (declare (ignore editor))
      (is string= *csvdt-test-utc* out)
      (true (tuatara.frontend.fake:fake-frame-showing f "csvdt -H -p -u0 -i 0,replace: 4 lines")))
    ;; RET runs the arguments offered as they are
    (multiple-value-bind (f editor out) (csvdt-test-run "M-x c s v d t - r u n - b u f f e r RET RET")
      (declare (ignore f editor))
      (is string= *csvdt-test-text* out))
    ;; the right arrow keeps them, to add to
    (multiple-value-bind (f editor out)
        (csvdt-test-run "M-x c s v d t - r u n - b u f f e r RET <right> SPC - u 0 SPC - i SPC 0 , r e p l a c e RET")
      (declare (ignore f editor))
      (true (search "10:00:00+00:00" out)))
    ;; the source is never changed
    (csvdt-test-run "M-x c s v d t - r u n - b u f f e r RET - H SPC - u 0 RET")
    (is string= *csvdt-test-text* (tuatara.buffer:buffer-string (tuatara.buffer:find-buffer "*scratch*")))))

(define-test (csvdt csvdt-options-asked-as-a-csv-buffer-opens)
  ;; a buffer turning to CSV mode has csvdt's options asked in the background, once while they are kept;
  ;; with no csvdt to ask, the buffer opens all the same and nothing is asked
  (let ((started '()) (kept nil))
    (sb-int:encapsulate 'tuatara:start-job-thread 'held
                        (lambda (f job work &rest arguments)
                          (declare (ignore f work arguments))
                          (push job started)))
    (sb-int:encapsulate 'csvdt::csvdt-options-kept-p 'told (lambda (f) (declare (ignore f)) kept))
    (unwind-protect
         (flet ((open-csv (name)
                  (let ((buffer (tuatara.buffer:make-buffer name :text "a,b")))
                    (unwind-protect (tuatara.modes:set-major-mode buffer 'tuatara:csv-mode)
                      (tuatara.buffer:kill-buffer buffer)))))
           (open-csv "csvdt asked")
           (is = 1 (count-if #'csvdt::csvdt-options-job-p started))
           (setf kept t)
           (open-csv "csvdt kept")
           (is = 1 (count-if #'csvdt::csvdt-options-job-p started))
           (sb-int:unencapsulate 'csvdt::csvdt-options-kept-p 'told)
           (let ((csvdt::*csvdt-program* "no-such-csvdt-program") (csvdt::*csvdt-options-cache* nil))
             (open-csv "csvdt missing"))
           (is = 1 (count-if #'csvdt::csvdt-options-job-p started)))
      (sb-int:unencapsulate 'csvdt::csvdt-options-kept-p 'told)
      (sb-int:unencapsulate 'tuatara:start-job-thread 'held))))

(define-test (csvdt csvdt-keys-in-csv-mode)
  (with-csvdt ()
    ;; C-c v r in a CSV buffer runs over the whole of it
    (multiple-value-bind (f editor out)
        (csvdt-test-run "C-c v r - H SPC - p SPC - u 0 SPC - i SPC 0 , r e p l a c e RET" :mode 'tuatara:csv-mode)
      (declare (ignore f editor))
      (is string= *csvdt-test-utc* out)
      (true (typep (tuatara:buffer-major-mode (tuatara.buffer:find-buffer "*csvdt output*")) 'tuatara:csv-mode)))))

(define-test (csvdt csvdt-completion-and-history)
  (with-csvdt ()
    ;; TAB completes the option before the cursor from those csvdt reports
    (multiple-value-bind (f editor out)
        (csvdt-test-run "M-x c s v d t - r u n - b u f f e r RET - - h a s TAB SPC - p RET")
      (declare (ignore editor))
      (is string= *csvdt-test-text* out)
      (true (tuatara.frontend.fake:fake-frame-showing f "csvdt --has-header -p: 4 lines")))
    ;; M-p brings back the line run before
    (csvdt-test-run "M-x c s v d t - r u n - b u f f e r RET - H SPC - p SPC - u 0 SPC - i SPC 0 , r e p l a c e RET")
    (multiple-value-bind (f editor out) (csvdt-test-run "M-x c s v d t - r u n - b u f f e r RET M-p RET")
      (declare (ignore f editor))
      (is string= *csvdt-test-utc* out))
    (is equal "-H -p -u0 -i 0,replace" (first csvdt::*csvdt-history*))))

(define-test (csvdt csvdt-run-region-takes-the-header)
  (with-csvdt ()
    ;; from the middle of the first row to the middle of the second: both rows, whole, the header from csvdt
    (multiple-value-bind (f editor out)
        (csvdt-test-run
         "M-x c s v d t - r u n - r e g i o n RET - H SPC - p SPC - u 0 SPC - i SPC 0 , r e p l a c e RET"
         :point 12 :mark 40)
      (declare (ignore editor))
      (is string= (format nil "to_utc,x~%2026-07-25T10:00:00+00:00,a~%2026-07-26T10:00:00+00:00,b~%") out)
      (true (tuatara.frontend.fake:fake-frame-showing f "selection widened to whole lines")))
    ;; without a header asked for, there is none to print
    (multiple-value-bind (f editor out)
        (csvdt-test-run
         "M-x c s v d t - r u n - r e g i o n RET - u 0 SPC - i SPC 0 , r e p l a c e RET"
         :point 33 :mark 61)
      (declare (ignore f editor))
      (is string= (format nil "2026-07-26T10:00:00+00:00,b~%") out))))

(defparameter *csvdt-test-commented*
  (format nil "# exported,\"by~%name,v~%x,1~%y,2~%")
  "A comment line holding a quote, a header and two rows.")

(define-test (csvdt csvdt-comment-option-leaves-records-to-csvdt)
  (with-csvdt ()
    (flet ((run (keys &rest options)
             (csvdt-test-forget-output)
             (apply #'run-keys-in-turns (list keys) :text *csvdt-test-commented* :width 140 options)
             (csvdt-test-output)))
      ;; the whole buffer, csvdt skipping the comment
      (is equal (format nil "name,v~%x,1~%y,2~%")
          (run "M-x c s v d t - r u n - b u f f e r RET - - c o m m e n t SPC ' # ' SPC - H SPC - p RET"))
      ;; a row below the comment, in either spelling: the header is csvdt's, the quote in the comment is no field
      (dolist (arguments '("- - c o m m e n t SPC ' # ' SPC - H SPC - p" "- - c o m m e n t = # SPC - H SPC - p"))
        (is equal (format nil "name,v~%y,2~%")
            (run (format nil "M-x c s v d t - r u n - r e g i o n RET ~a RET" arguments) :point 26 :mark 29)))
      ;; banked lines the same
      (csvdt-test-forget-output)
      (run-keys (list (lambda () (tuatara.defaults::bank-span (tuatara.command:current-buffer) (cons 22 26)))
                      "M-x c s v d t - r u n - b a n k e d RET - - c o m m e n t = # SPC - H SPC - p RET")
                :text *csvdt-test-commented* :width 140)
      (is equal (format nil "name,v~%x,1~%") (csvdt-test-output)))))

(defparameter *csvdt-test-spanning*
  (format nil "h,v~%1,\"a~%b\"~%2,c~%")
  "A header and two rows, the first holding a line end in a quoted field.")

(define-test (csvdt csvdt-widens-to-whole-records)
  (with-csvdt ()
    (csvdt-test-forget-output)
    ;; the second line of the first row picked, inside its quoted field: csvdt takes the whole row and says so
    (multiple-value-bind (f editor)
        (run-keys-in-turns (list "M-x c s v d t - r u n - r e g i o n RET - H SPC - p RET")
                           :text *csvdt-test-spanning* :width 140 :point 10 :mark 12)
      (declare (ignore editor))
      (is equal (format nil "h,v~%1,\"a~%b\"~%") (csvdt-test-output))
      (true (tuatara.frontend.fake:fake-frame-showing f "widened to whole records: lines 2-3")))))

(defun csvdt-test-widest-text (width)
  "A header, one record of WIDTH fields and WIDTH records of one field: -f=widest
pads every record to the wide one, so what csvdt writes grows as WIDTH squared."
  (with-output-to-string (s)
    (format s "a,b~%~{~d~^,~}~%" (alexandria:iota width))
    (dotimes (i width) (format s "0~%"))))

(define-test (csvdt csvdt-output-limited)
  (with-csvdt ()
    (let ((text (csvdt-test-widest-text 300))
          (keys "M-x c s v d t - r u n - b u f f e r RET - H SPC - p SPC - f = w i d e s t RET"))
      ;; within the limit the padded output is shown
      (csvdt-test-forget-output)
      (run-keys-in-turns (list keys) :text text)
      (true (< (* 50 (length text)) (length (csvdt-test-output))))
      ;; past it csvdt is ended, the echo area says so and nothing is shown
      (csvdt-test-forget-output)
      (let ((multiple csvdt::*csvdt-output-multiple*) (least csvdt::*csvdt-least-output-limit*))
        (setf csvdt::*csvdt-output-multiple* 2 csvdt::*csvdt-least-output-limit* 0)
        (unwind-protect
             (multiple-value-bind (f editor)
                 (run-keys-in-turns (list keys) :text text :width 200)
               (declare (ignore editor))
               (is eq nil (csvdt-test-output))
               (true (tuatara.frontend.fake:fake-frame-showing f "csvdt was ended: it wrote more than")))
          (setf csvdt::*csvdt-output-multiple* multiple csvdt::*csvdt-least-output-limit* least)))
      ;; nor more than the editor's memory may spare, whatever the multiple and the floor say
      (csvdt-test-forget-output)
      (sb-int:encapsulate 'tuatara:heap-budget 'csvdt-small-heap
                          (lambda (function &rest arguments)
                            (declare (ignore function arguments))
                            1000))
      (unwind-protect
           (multiple-value-bind (f editor) (run-keys-in-turns (list keys) :text text :width 200)
             (declare (ignore editor))
             (is eq nil (csvdt-test-output))
             (true (tuatara.frontend.fake:fake-frame-showing f "csvdt was ended: it wrote more than")))
        (sb-int:unencapsulate 'tuatara:heap-budget 'csvdt-small-heap)))))

(define-test (csvdt csvdt-crlf)
  (with-csvdt ()
    ;; a buffer ending its lines with CR LF reaches csvdt with LF alone
    (csvdt-test-forget-output)
    (run-keys-in-turns (list
                        "M-x c s v d t - r u n - b u f f e r RET - H SPC - p SPC - u 0 SPC - i SPC 0 , r e p l a c e RET")
                       :text (format nil "ts,x~a~%2026-07-25T12:00:00+02:00,a~a~%" #\Return #\Return) :crlf t)
    (is string= (format nil "to_utc,x~%2026-07-25T10:00:00+00:00,a~%") (csvdt-test-output))))

(define-test (csvdt csvdt-run-banked)
  (with-csvdt ()
    (csvdt-test-forget-output)
    ;; the first and third rows banked: sent as one file, the header in front, the row between left out
    (multiple-value-bind (f editor)
        (run-keys (list (lambda ()
                          (let ((b (tuatara.command:current-buffer)))
                            (tuatara.defaults::bank-span b (cons 5 33))
                            (tuatara.defaults::bank-span b (cons 61 89))))
                        "M-x c s v d t - r u n - b a n k e d RET - H SPC - p SPC - u 0 SPC - i SPC 0 , r e p l a c e RET")
                  :text *csvdt-test-text* :width 120)
      (declare (ignore editor))
      (is string= (format nil "to_utc,x~%2026-07-25T10:00:00+00:00,a~%2026-07-27T10:00:00+00:00,c~%")
          (csvdt-test-output))
      (true (tuatara.frontend.fake:fake-frame-showing f "3 lines from 2 stretches"))
      ;; the lines stay banked
      (is = 2 (length (tuatara:banked-spans (tuatara.buffer:find-buffer "*scratch*")))))
    ;; dwim takes the banked lines and the selection together, a line in both sent once
    (multiple-value-bind (f editor)
        (run-keys (list (lambda ()
                          (let ((b (tuatara.command:current-buffer)))
                            (tuatara.defaults::bank-span b (cons 5 33))
                            (setf (tuatara.buffer:buffer-mark b) 20 (tuatara.buffer:buffer-point b) 40
                                  (tuatara.buffer:buffer-mark-active-p b) t)))
                        "M-x c s v d t - r u n - d w i m RET - H SPC - p SPC - u 0 SPC - i SPC 0 , r e p l a c e RET")
                  :text *csvdt-test-text* :width 120)
      (declare (ignore f editor))
      (is string= (format nil "to_utc,x~%2026-07-25T10:00:00+00:00,a~%2026-07-26T10:00:00+00:00,b~%")
          (csvdt-test-output)))
    ;; describe-run counts what a run would cover without running
    (multiple-value-bind (f editor)
        (run-keys (list (lambda () (tuatara.defaults::bank-span (tuatara.command:current-buffer) (cons 5 33)))
                        "M-x c s v d t - d e s c r i b e - r u n RET")
                  :text *csvdt-test-text* :width 120)
      (declare (ignore editor))
      (true (tuatara.frontend.fake:fake-frame-showing f "csvdt would run over 1 line in 1 stretch")))))

(define-test (csvdt csvdt-output-buffer)
  (with-csvdt ()
    ;; a run over *csvdt output* itself: its banks let go, its text replaced, still writable
    (csvdt-test-run "M-x c s v d t - r u n - b u f f e r RET RET")
    (let ((out (tuatara.buffer:find-buffer "*csvdt output*")))
      (tuatara.defaults::bank-span out (cons 5 33))
      (run-keys (list (lambda () (tuatara.command:show-buffer out))
                      "M-x c s v d t - r u n - b u f f e r RET - H SPC - p SPC - u 0 SPC - i SPC 0 , r e p l a c e RET")
                :width 120)
      (is string= *csvdt-test-utc* (csvdt-test-output))
      (is eq out (tuatara.buffer:find-buffer "*csvdt output*"))
      (false (tuatara:banked-p out))
      (finish (tuatara:check-writable out)))))

(define-test (csvdt csvdt-refusals)
  (with-csvdt ()
    ;; a file named among the arguments would take the lines' place
    (with-test-directory (dir)
      (let ((file (namestring (merge-pathnames "sales.csv" dir))))
        (alexandria:write-string-into-file "a,b" file)
        (let ((b (tuatara.buffer:make-buffer "refused" :text "a,b")))
          (unwind-protect (fail (csvdt::csvdt-run b '((0 . 3)) (list "-H" file)))
            (tuatara.buffer:kill-buffer b)))))
    ;; a value apart from its option is no file, though a file of that name is there
    (with-test-directory (dir)
      (alexandria:write-string-into-file "a,b" (merge-pathnames "7" dir))
      (is equal '() (csvdt::csvdt-file-arguments '("-u" "7") (namestring dir)))
      (is equal '("7") (csvdt::csvdt-file-arguments '("-H" "7") (namestring dir))))
    ;; csvdt's own reason, with its exit status
    (multiple-value-bind (f editor) (csvdt-test-run "M-x c s v d t - r u n - b u f f e r RET - H SPC - u 9 RET")
      (declare (ignore editor))
      (true (tuatara.frontend.fake:fake-frame-showing f "csvdt exited")))
    ;; a program that is not there says which setting to set
    (let ((csvdt::*csvdt-program* "/no/such/csvdt"))
      (fail (csvdt::csvdt-program)))))

(defun csvdt-test-take-in-consed (rows)
  "Octets consed per octet of output when a run of csvdt over ROWS rows is
put in *csvdt output* and its lines counted, as its take-in does; and the
line total."
  (let* ((text (with-output-to-string (s)
                 (format s "ts,x~%")
                 (dotimes (i rows) (format s "2026-07-25T12:00:00+02:00,row ~d~%" i))))
         (b (tuatara.buffer:make-buffer "csvdt take-in" :text text)))
    (unwind-protect
         (let ((job (csvdt::make-csvdt-job
                     :buffer b :program *csvdt-test-program* :arguments (list "-H" "-p")
                     :rope (tuatara.buffer:buffer-text b) :input (cons 0 (tuatara.buffer:buffer-size b)))))
           (csvdt::csvdt-work job)
           (let* ((before (sb-ext:get-bytes-consed))
                  (out (csvdt::csvdt-fill-output (csvdt::csvdt-job-output job)))
                  (lines (csvdt::csvdt-line-total (csvdt::csvdt-job-output job))))
             (values (/ (- (sb-ext:get-bytes-consed) before) (max 1 (tuatara.buffer:buffer-size out)))
                     lines)))
      (tuatara.buffer:kill-buffer b))))

(define-test (csvdt csvdt-take-in-conses-little)
  ;; the output reaches *csvdt output* as csvdt wrote it, never made a string on the editor's thread
  (with-csvdt ()
    ;; once before, for what entering the mode costs only the first time
    (csvdt-test-take-in-consed 100)
    (multiple-value-bind (small small-lines) (csvdt-test-take-in-consed 20000)
      (multiple-value-bind (large large-lines) (csvdt-test-take-in-consed 80000)
        (is = 20001 small-lines)
        (is = 80001 large-lines)
        (true (< small 1.8) "~,3f octets consed per octet of output, 20,000 rows" small)
        (true (< large 1.8) "~,3f octets consed per octet of output, 80,000 rows" large)))))

(define-test (csvdt csvdt-asked-while-keys-are-read)
  ;; a slow csvdt asked for its version: the editor says it waits and reads keys meanwhile
  (with-test-directory (dir)
    (let ((program (namestring (merge-pathnames "csvdt" dir))))
      (with-open-file (o program :direction :output)
        (format o "#!/bin/sh~%sleep 0.5~%echo 'csvdt 9.9.9'~%"))
      (sb-posix:chmod program #o755)
      (let ((csvdt::*csvdt-program* program) (tuatara-user:*modal-editing* nil))
        (multiple-value-bind (f editor result)
            (waiting-session (lambda (e) (declare (ignore e)) (csvdt::csvdt-version-string)) "")
          (declare (ignore editor))
          (is string= "csvdt 9.9.9" result)
          (true (tuatara.frontend.fake:fake-frame-showing f "Asking csvdt... (C-g stops waiting)")))))))

(define-test (csvdt arguments-asked-without-waiting)
  ;; the prompt asks at once, naming no version: csvdt's options are asked in the background meanwhile;
  ;; any program that is there stands in for csvdt, since a missing one is not asked
  (let ((prompt nil) (started '()))
    (sb-int:encapsulate 'tuatara:read-string 'csvdt-prompt
                        (lambda (function asked &rest keys)
                          (declare (ignore function keys))
                          (setf prompt asked)
                          "-p"))
    (sb-int:encapsulate 'tuatara:start-job-thread 'csvdt-prompt
                        (lambda (function job &rest arguments)
                          (declare (ignore function arguments))
                          (push job started)))
    (unwind-protect
         (let ((csvdt::*csvdt-history* '()) (csvdt::*csvdt-options-cache* nil)
               (csvdt::*csvdt-program* (tuatara:find-program "sh")))
           (is equal '("-p") (csvdt::csvdt-read-arguments)))
      (sb-int:unencapsulate 'tuatara:read-string 'csvdt-prompt)
      (sb-int:unencapsulate 'tuatara:start-job-thread 'csvdt-prompt))
    (is string= "csvdt arguments: " prompt)
    (true (some #'csvdt::csvdt-options-job-p started))))

(define-test (csvdt relative-program-refused)
  ;; a relative program would be whatever file of that name stands beside the CSV file
  (let ((csvdt::*csvdt-program* "./target/release/csvdt"))
    (true (search "relative path"
                  (handler-case (progn (csvdt::csvdt-program) "")
                    (error (e) (princ-to-string e)))))))

(define-test (csvdt program-in-a-directory-named-with-brackets)
  ;; [, * and ? in the program's path are letters of its name, nothing else
  (with-test-directory (dir)
    (let* ((directory (format nil "~a[new]/" (namestring dir)))
           (program (concatenate 'string directory "csvdt"))
           (csvdt::*csvdt-options-cache* nil))
      (sb-posix:mkdir directory #o700)
      (with-open-file (o (sb-ext:parse-native-namestring program) :direction :output)
        (format o "#!/bin/sh~%case \"$1\" in~%--version) echo 'csvdt 9.9.9';;~%~
                   *) printf '# csvdt-option-list 1\\n-H\\t--has-header\\t\\t\\n';;~%esac~%"))
      (sb-posix:chmod program #o755)
      (let ((csvdt::*csvdt-program* program))
        (is equal "--has-header" (getf (first (csvdt::csvdt-option-records)) :long))
        (is string= "csvdt 9.9.9" (csvdt::csvdt-cached-version))))))

(define-test (csvdt csvdt-run-shut-in)
  ;; csvdt runs shut in, shown the program alone, given the lines on its standard input; what it prints is
  ;; the output as before
  (let* ((b (tuatara.buffer:make-buffer "csvdt shut in" :text (format nil "ts,x~%1,a~%")))
         (job (csvdt::make-csvdt-job :buffer b :program "/usr/bin/csvdt" :arguments (list "-p")
                                     :rope (tuatara.buffer:buffer-text b)
                                     :input (cons 0 (tuatara.buffer:buffer-size b))))
         (given nil))
    (sb-int:encapsulate 'tuatara.io:sandbox-run 'csvdt-shut-in
                        (lambda (function program arguments &rest keys)
                          (declare (ignore function))
                          (setf given (list program arguments (getf keys :directories)
                                            (tuatara.io:read-fd-octets (getf keys :input))))
                          (values (tuatara.text:string-octets (format nil "x~%a~%")) :done "")))
    (unwind-protect (csvdt::csvdt-work job)
      (sb-int:unencapsulate 'tuatara.io:sandbox-run 'csvdt-shut-in)
      (tuatara.buffer:kill-buffer b))
    (is equal '("/usr/bin/csvdt" ("-p") ("/usr/bin/csvdt")) (subseq given 0 3))
    (is string= (format nil "ts,x~%1,a~%") (tuatara.text:octets-string (fourth given)))
    (is eql 0 (csvdt::csvdt-job-exit job))
    (is string= (format nil "x~%a~%") (tuatara.text:octets-string (csvdt::csvdt-job-output job)))))

(define-test (csvdt readers-documented)
  (true (search "csvdt program" (documentation 'csvdt::csvdt-job-program 'function)))
  (true (search "--lines" (documentation 'csvdt::csvdt-job-ranges 'function))))
