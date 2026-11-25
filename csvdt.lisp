;;;; csvdt.lisp --- csvdt run over a buffer, a selection or banked lines, its result in a buffer of its own.
;;;; Copyright (C) 2025-2026 Michael A Jones.  GPL-3.0-or-later; see LICENSE.
;;;; Needs: Tuatara 0.90.40
;;;;
;;;; A package, not part of the editor: loaded by (load-package "csvdt") in
;;;; the init file. It drives csvdt (github.com/YardQuit/csvdt), a program of
;;;; its own that converts the timestamps and durations of CSV records.
;;;;
;;;; Almost nothing about csvdt's options is written down here. The help is
;;;; csvdt's own --help, and the options offered for completion come from
;;;; csvdt --list-options, which csvdt prints from its own definitions: a
;;;; csvdt that gains an option is usable here at once. One is named, --lines,
;;;; which is how a run over part of a buffer says which lines it means: csvdt
;;;; reads the buffer as it reads any file, so where a record begins, which
;;;; lines are comments and which record is the header are for csvdt to say,
;;;; and nothing here reads the text as CSV.
;;;;
;;;; The text goes to csvdt on its standard input from a job in the background
;;;; (M-x stop-job stops it); what it writes goes to *csvdt output*, and the
;;;; source buffer is never changed. Nothing is run through a shell. Needs
;;;; csvdt 1.2.0 or later.

(defpackage #:csvdt
  (:use #:cl #:tuatara)
  (:documentation "csvdt run over a buffer, a selection or banked lines, its result in a buffer of its own."))

(in-package #:csvdt)

(declare-package-needs
 '("csvdt" "converts the timestamps and durations of CSV records" :required t
   :install "get csvdt 1.2.0 or later from github.com/YardQuit/csvdt"))

;;; Settings

(define-package-setting *csvdt-program* "csvdt"
  "The csvdt program to run.
- a name: looked for on the PATH.
- a full path, from / or ~: that file, never looked for on the PATH. A
  relative path is refused, for it would run whatever file of that name
  stands in the directory of the CSV file."
  :values string)

(define-package-setting *csvdt-default-arguments* "-H -p"
  "The arguments a csvdt command line starts with, selected.
Typing replaces them, \\<minibuffer>\\[minibuffer-forward-char] keeps them to
add to, \\[minibuffer-finish] runs them as they are. The default is for a file
with a header row, the header printed. Text with csvdt's options in it, \"\" for
none.

They are selected rather than only offered because the two mistakes are not
alike. Leaving the header option off a file that has a header is loud: the
header comes back as parse_err. Giving it to a file that has none is quiet:
the first row is taken for a header and, by where the conversion puts its
column, either goes through unconverted or is lost. Arguments to be noticed
and deleted point at the quiet mistake; arguments to be kept do not."
  :values string)

(define-package-setting *csvdt-region-carries-header* t
  "Obsolete: no longer read, and removed in the next major version.
It said whether the buffer's header line went in front of a selection or
banked lines below it. csvdt is now given the whole buffer and the lines
selected, and under its header option the buffer's first record is always the
header, which is what t gave."
  :values boolean)

(define-package-setting *csvdt-header-options* '("-H" "--has-header")
  "Obsolete: no longer read, and removed in the next major version.
It named the csvdt options saying the first record is a header, for
*CSVDT-REGION-CARRIES-HEADER*. csvdt now reads the header itself."
  :values (list-of string))

(define-package-setting *csvdt-single-quote-options* '("--single-quote")
  "Obsolete: no longer read, and removed in the next major version.
It named the csvdt options making ' the quote character, for finding where a
record begins. csvdt now finds that itself."
  :values (list-of string))

(define-package-setting *csvdt-read-delimiter-options* '("--read-delimiter")
  "Obsolete: no longer read, and removed in the next major version.
It named the csvdt options setting the delimiter fields are read with, for
finding where a record begins. csvdt now finds that itself."
  :values (list-of string))

(define-package-setting *csvdt-comment-options* '("--comment")
  "Obsolete: no longer read, and removed in the next major version.
It named the csvdt options naming a comment character, with which a run over
part of the buffer was refused. csvdt now reads comment lines in such a run as
in any other."
  :values (list-of string))

(define-package-setting *csvdt-output-mode* 'csv-mode
  "The major mode of *csvdt output*.
A mode that cannot be entered leaves the buffer in fundamental-mode rather
than losing a run csvdt has done.
- a mode's name: the buffer is put in it, csv-mode by default."
  :values function)

(define-package-setting *csvdt-output-multiple* 8
  "How much csvdt may write for a run, as a multiple of what it is given:
eight times its input by default, and never less than
*CSVDT-LEAST-OUTPUT-LIMIT*, nor more than a quarter of the editor's free
memory when the run starts. A run that writes more is ended and nothing of it
shown, for what csvdt writes is held in the editor's memory. Some options
make the output much longer than the input (-f=widest pads every record to the
widest one); raise this for such a run.
- a whole number, 1 or more: the multiple."
  :values (integer 1 *))

(defparameter *csvdt-output-name* "*csvdt output*"
  "The name of the buffer csvdt's output is shown in.")

(defparameter *csvdt-wait* 1/2
  "Seconds a run waits for csvdt before going on in the background.")

(defparameter *csvdt-least-output-limit* (* 64 1024 1024)
  "The octets csvdt may write however little it is given (CSVDT-OUTPUT-LIMIT).")

(defparameter *csvdt-piece* (* 1024 1024)
  "Octets read from the text and written to csvdt at a time.")

(defconstant +csvdt-option-list-format+ 1
  "The version of csvdt's --list-options format this package reads. csvdt
prints it on the first line; another means the fields may not mean what is
assumed here, and the list is read from --help instead.")

(defvar *csvdt-options-cache* nil
  "The options of the csvdt last asked, as (PROGRAM STAMP VERSION . RECORDS):
PROGRAM its path, STAMP what the system says of it. A rebuilt csvdt has
another stamp and is asked again; one unchanged is not run again to find
that out. VERSION is its --version line, asked at the same time.")

(defvar *csvdt-history* '()
  "The csvdt command lines run, the latest first, gone back through with
\\<minibuffer>\\[minibuffer-previous-history] while csvdt arguments are read.")

;;; The program

(defun csvdt-space-p (char)
  "True when CHAR separates arguments in a csvdt command line: a space, a tab,
a line end, a form feed or a vertical tab."
  (member char '(#\Space #\Tab #\Newline #\Return #\Page #.(code-char 11))))

(defun csvdt-program ()
  "The full path of the csvdt program (*CSVDT-PROGRAM*), ~ there your home
directory; an error naming what is the matter when there is none, or when it
is a relative path."
  (let ((path (if (uiop:string-prefix-p "~" *csvdt-program*)
                  (native (expand-path *csvdt-program*))
                  *csvdt-program*)))
    (cond ((not (find #\/ path))
           (or (find-program path)
               (error "Cannot find ~a on the PATH: set *csvdt-program* to its full path" path)))
          ((char/= (char path 0) #\/)
           (error "*csvdt-program* is ~a, a relative path: set it to the program's full path" *csvdt-program*))
          (t (case (path-kind path)
               (:directory
                (error "~a is a directory, not the csvdt program: set *csvdt-program* to the program itself" path))
               ((nil) (error "Cannot find ~a: set *csvdt-program*" path))
               (t (or (find-program path)
                      (error "~a cannot be run: chmod +x it, or set *csvdt-program* to one that can" path))))))))

(defun csvdt-output-of (arguments &key (interruptible t))
  "What csvdt writes when run with ARGUMENTS and no input; NIL when it fails,
so that a csvdt declining them is gone around rather than broken on. At most
ten seconds; with INTERRUPTIBLE, for a command, the editor reading keys
meanwhile and \\`C-g' giving up, else the thread asking simply waits."
  (multiple-value-bind (output ok)
      (program-output (cons (csvdt-program) arguments)
                      :seconds 10
                      :wait (and interruptible
                                 (lambda (thread seconds)
                                   (wait-interruptibly thread :message "Asking csvdt..." :seconds seconds))))
    (and ok output)))

(defun csvdt-version-string (&key (interruptible t))
  "csvdt's --version line, which names the time zone database built into it;
INTERRUPTIBLE as CSVDT-OUTPUT-OF takes it."
  (string-trim '(#\Space #\Newline) (or (csvdt-output-of '("--version") :interruptible interruptible) "")))

(defun csvdt-help-text (&key (interruptible t))
  "csvdt's --help; INTERRUPTIBLE as CSVDT-OUTPUT-OF takes it."
  (or (csvdt-output-of '("--help") :interruptible interruptible) (error "~a --help failed" *csvdt-program*)))

;;; Its options, from its own list

(defun csvdt-parse-option-list (text)
  "The options in TEXT, what csvdt --list-options prints, each a plist of
:short, :long, :value and :separator; NIL when TEXT is not in a format this
package reads (+CSVDT-OPTION-LIST-FORMAT+)."
  (let ((lines (remove "" (uiop:split-string (or text "") :separator '(#\Newline)) :test #'string=)))
    (when (equal (first lines) (format nil "# csvdt-option-list ~d" +csvdt-option-list-format+))
      (loop for line in (rest lines)
            for fields = (uiop:split-string line :separator '(#\Tab))
            unless (uiop:string-prefix-p "#" line)
              collect (list :short (nth 0 fields) :long (nth 1 fields)
                            :value (nth 2 fields) :separator (nth 3 fields))))))

(defun csvdt-parse-help (help)
  "The options HELP, csvdt's --help, lists, for a csvdt too old to list them
itself: each \"  -x, --xxx\" or \"      --xxx\" at the start of a line, the
first of each, the later ones being its prose. A help page does not say
which options take a value in a way worth reading, so :value is NIL,
not known, and CSVDT-FILE-ARGUMENTS guesses at no filenames without it."
  (let ((records '()))
    (cl-ppcre:do-register-groups (short long)
        ("(?m)^[ \\t]+(?:-([A-Za-z]), )?--([A-Za-z][A-Za-z0-9-]*)" help)
      (let ((long (concatenate 'string "--" long)))
        (unless (find long records :key (lambda (record) (getf record :long)) :test #'equal)
          (push (list :short (if short (concatenate 'string "-" short) "") :long long :value nil :separator nil)
                records))))
    (nreverse records)))

(defun csvdt-option-records (&key (interruptible t))
  "csvdt's options as records (CSVDT-PARSE-OPTION-LIST), from its own list,
else from its --help; kept while the program is the same file, unchanged
\(*CSVDT-OPTIONS-CACHE*). INTERRUPTIBLE as CSVDT-OUTPUT-OF takes it."
  (let* ((program (csvdt-program))
         (stamp (path-stamp program)))
    (if (and (equal (first *csvdt-options-cache*) program)
             (equalp (second *csvdt-options-cache*) stamp))
        (nthcdr 3 *csvdt-options-cache*)
        (let ((records (or (csvdt-parse-option-list
                            (csvdt-output-of '("--list-options") :interruptible interruptible))
                           (csvdt-parse-help (csvdt-help-text :interruptible interruptible)))))
          (setf *csvdt-options-cache*
                (list* program stamp (csvdt-version-string :interruptible interruptible) records))
          records))))

(define-record (csvdt-options-job (:include job) (:constructor make-csvdt-options-job (buffer)) (:copier nil))
  "Asking csvdt for its options and its version in the background, kept for
the commands (CSVDT-OPTION-RECORDS).")

(define-job-words csvdt-options-job
  :doing "Asking csvdt for its options"
  :description "Asking csvdt for its options and its version"
  :verb "ask csvdt for its options"
  :left-words "nothing asked"
  :at-exit :quiet)

(defmethod job-take-in ((job csvdt-options-job))
  "Nothing to take in: what csvdt said is kept already."
  nil)

(defun csvdt-ask-options-soon ()
  "Have csvdt's options and version asked in the background while a command
line is typed, so that completing an option and the run after it find them
kept; a csvdt that cannot be asked is said by the command that needs it."
  (unless (some #'csvdt-options-job-p (jobs-of (current-buffer) :running t))
    (start-job-thread (make-csvdt-options-job (current-buffer))
                      (lambda (job)
                        (declare (ignore job))
                        (handler-case (csvdt-option-records :interruptible nil)
                          (error () nil)))
                      :name "tuatara csvdt options")))

(defun csvdt-cached-version ()
  "csvdt's version line, asked with its options rather than at each command."
  (csvdt-option-records)
  (third *csvdt-options-cache*))

(defun csvdt-options ()
  "The options to offer for completion, short and long; an option whose value
must be joined with = offered with it too, since a value written apart would
be read as a filename."
  (let ((options '()))
    (dolist (record (csvdt-option-records))
      (dolist (form (list (getf record :short) (getf record :long)))
        (when (plusp (length form))
          (pushnew form options :test #'string=)
          (when (equal (getf record :separator) "equals")
            (pushnew (concatenate 'string form "=") options :test #'string=)))))
    (nreverse options)))

;;; Reading a command line

;; Read whole and split as a shell would, not as a comma-separated list: a
;; comma is csvdt's own separator inside a value (-a 1,0, -i 0,replace,
;; -o0,+02:00).

(defun csvdt-split-arguments (line)
  "LINE split into arguments as a shell would: a quoted argument may hold a
space, an unquoted one a comma, which csvdt's value lists need. Either quote
is taken; in double quotes the escapes \\t \\n \\r \\ \\\" and no others, in
single quotes none. So a lone quote is written in the other kind, and a value
keeping its backslashes in single quotes. Outside quotes a backslash is
itself, unlike a shell: a Windows path typed as a value comes through whole."
  (multiple-value-bind (words ok why) (command-words line :backslash :escapes)
    (unless ok (error "Cannot read ~a: ~a" line why))
    words))

(defun csvdt-argument-at (text point options)
  "The argument of TEXT, a csvdt command line, that ends at POINT, to be
completed from OPTIONS: three values, where it starts, POINT, and OPTIONS."
  (let ((space (position-if #'csvdt-space-p text :end point :from-end t)))
    (values (if space (1+ space) 0) point options)))

(defun csvdt-complete-argument ()
  "Complete the argument before the minibuffer's cursor from csvdt's options, in
a list beside it: \\<minibuffer>\\[minibuffer-complete] while csvdt arguments
are read."
  (let ((options (handler-case (csvdt-options)
                   (error (e) (message "~a" e) (return-from csvdt-complete-argument nil)))))
    (complete-in-minibuffer (lambda (text point) (csvdt-argument-at text point options))
                            :constituent (lambda (char) (not (csvdt-space-p char))) :keep-order t)))

(defun csvdt-read-arguments ()
  "Read a csvdt command line and split it (CSVDT-SPLIT-ARGUMENTS). It starts
as *CSVDT-DEFAULT-ARGUMENTS*, selected: typing replaces it,
\\<minibuffer>\\[minibuffer-forward-char] keeps it to add to,
\\[minibuffer-finish] runs it as it is. \\[minibuffer-complete] completes
the option before the cursor, and \\[minibuffer-previous-history] and
\\[minibuffer-next-history] go back and forth through the lines run before.
csvdt's options are asked in the background meanwhile (CSVDT-ASK-OPTIONS-SOON)."
  (csvdt-ask-options-soon)
  (let ((line (read-string "csvdt arguments: "
                           :initial *csvdt-default-arguments* :select-initial t
                           :complete #'csvdt-complete-argument :history *csvdt-history*)))
    (unless (equal line (first *csvdt-history*))
      (push line *csvdt-history*))
    (csvdt-split-arguments line)))

;;; What the arguments say

(defun csvdt-shorts-taking-a-separate-value ()
  "The short options whose value may be the next argument. One whose value
must be joined with = takes none apart: written apart, its value stands
where the filename goes."
  (loop for record in (csvdt-option-records)
        for short = (getf record :short)
        when (and (plusp (length short))
                  (member (getf record :value) '("required" "optional") :test #'equal)
                  (not (equal (getf record :separator) "equals")))
          collect short))

(defun csvdt-expects-a-following-value (argument)
  "True when ARGUMENT is an option whose value is the argument after it: not
when its value is joined, when it takes none, or when it must be joined with =."
  (cond ((uiop:string-prefix-p "--" argument)
         (and (not (find #\= argument))
              (some (lambda (record)
                      (and (equal (getf record :long) argument)
                           (member (getf record :value) '("required" "optional") :test #'equal)
                           (not (equal (getf record :separator) "equals"))))
                    (csvdt-option-records))))
        ((and (> (length argument) 1) (char= (char argument 0) #\-))
         ;; a cluster ends at its first short taking a value, which takes the
         ;; next argument only when nothing follows it: -Hu 0 does, -Hu0 not
         (let ((valued (csvdt-shorts-taking-a-separate-value)))
           (loop for index from 1 below (length argument)
                 when (member (format nil "-~c" (char argument index)) valued :test #'string=)
                   return (= index (1- (length argument))))))))

(defun csvdt-file-arguments (arguments directory)
  "The ARGUMENTS csvdt would read as a file, those naming a file in
DIRECTORY. These commands give csvdt the lines on its standard input, and a
file named replaces them rather than adding to them, with a result looking
exactly like a run over the lines. One naming nothing on disk is left to
csvdt, whose own error says it better. When the options' records cannot say
which options take a value apart (those read from --help), nothing is
reported: a value taken for a filename would refuse a good run."
  (when (some (lambda (record) (getf record :value)) (csvdt-option-records))
    (let ((files '()) (positional nil))
      (loop while arguments
            do (let ((argument (pop arguments)))
                 (cond ((and (not positional) (string= argument "--")) (setf positional t))
                       ((and (not positional) (csvdt-expects-a-following-value argument)) (pop arguments))
                       ((and (not positional) (> (length argument) 1) (char= (char argument 0) #\-)))
                       ;; csvdt does not expand ~, so neither is it expanded here
                       ((and (plusp (length argument)) (char/= (char argument 0) #\~)
                             (eq :regular (path-kind (if (char= (char argument 0) #\/)
                                                         argument
                                                         (path-join directory argument)))))
                        (push argument files)))))
      (nreverse files))))

;;; Whole lines

(defun csvdt-line-start (rope position)
  "Where the line of ROPE holding POSITION starts."
  (if (zerop (rope-octet-length rope)) 0 (rope-line-start rope (min position (rope-octet-length rope)))))

(defun csvdt-next-line-start (rope position)
  "Where the line after POSITION's line of ROPE starts, or the text's end."
  (let ((size (rope-octet-length rope)))
    (if (>= position size)
        size
        (min size (1+ (rope-line-end rope position))))))

(defun csvdt-line-start-p (rope position)
  "True when POSITION of ROPE is at the start of a line."
  (or (zerop position) (= 10 (rope-octet rope (1- position)))))

(defun csvdt-line-end-p (rope position)
  "True when POSITION of ROPE is at the end of a line or of the text."
  (or (>= position (rope-octet-length rope))
      (member (rope-octet rope position) '(10 13))))

(defun csvdt-whole-lines (rope start end)
  "START..END of ROPE widened to whole lines, as (START . END). Half a line is
half a record, which csvdt would read as a short value rather than as damage.
An END at the start of a line stops there, the line before having been taken
to its newline."
  (let ((from (csvdt-line-start rope start))
        (to (if (and (> end start) (csvdt-line-start-p rope end)) end (csvdt-next-line-start rope end))))
    (cons from (max from to))))

(defun csvdt-settle (rope input ranges)
  "RANGES of ROPE as csvdt is told of them: widened to whole lines, kept
inside INPUT, (START . END), the part of the text csvdt is given, and made
one list in order, ranges that touch becoming one. Two values: the ranges,
and true when widening to lines changed them."
  (let ((lines (mapcar (lambda (range) (csvdt-whole-lines rope (car range) (cdr range))) ranges)))
    (values (merge-ranges (loop for (start . end) in lines
                                for from = (max start (car input))
                                for to = (min end (cdr input))
                                when (< from to) collect (cons from to)))
            (not (equal lines ranges)))))

(defun csvdt-newlines-between (rope start end)
  "How many line ends ROPE holds from START to END."
  (let ((piece (make-array 65536 :element-type '(unsigned-byte 8)))
        (total 0))
    (loop while (< start end)
          do (let ((n (min (length piece) (- end start))))
               (incf total (count 10 piece :end (rope-copy-into rope start (+ start n) piece)))
               (incf start n)))
    total))

(defun csvdt-lines-argument (rope start ranges)
  "RANGES of ROPE, each (START . END) of whole lines, as the lines they hold
in the form csvdt's --lines reads (\"3-5,9\"), the line at START being line 1."
  (let ((line 1) (at start) (parts '()))
    (loop for (from . to) in ranges
          do (incf line (csvdt-newlines-between rope at from))
             (let ((last (+ line (csvdt-newlines-between rope from to)
                            (if (= 10 (rope-octet rope (1- to))) -1 0))))
               (push (if (= line last) (format nil "~d" line) (format nil "~d-~d" line last)) parts)
               (setf line (1+ last) at to)))
    (format nil "~{~a~^,~}" (nreverse parts))))

(defun csvdt-cut-note (rope input ranges)
  "What the narrowing, INPUT (START . END) of ROPE, cuts of the lines of
RANGES, in words, or NIL: csvdt is given the text from START to END, so a
line the narrowing begins or ends inside reaches it in part. The end matters
only when RANGES reach it."
  (let ((start (not (csvdt-line-start-p rope (car input))))
        (end (and (= (cdr (car (last ranges))) (cdr input))
                  (not (or (csvdt-line-start-p rope (cdr input)) (csvdt-line-end-p rope (cdr input)))))))
    (cond ((and start end) "first and last lines cut short by the narrowing")
          (start "first line cut short by the narrowing")
          (end "last line cut short by the narrowing"))))

;;; What is picked out

(defun csvdt-selection-ranges (buffer)
  "The selection of BUFFER as a list of (START . END), or NIL: a line
selection by its whole lines, a rectangle by the rows it spans, its columns
being csvdt's own to pick."
  (multiple-value-bind (start end) (and (eq buffer (current-buffer)) (selection-range :widen t))
    (and start (< start end) (list (cons start end)))))

(defun csvdt-mid-line-p (rope ranges)
  "True when one of RANGES of ROPE starts or ends inside a line, so a run
covers whole rows the selection only touched. The end of a line, before its
newline, is not inside it."
  (some (lambda (range)
          (or (not (csvdt-line-start-p rope (car range)))
              (not (or (csvdt-line-start-p rope (cdr range)) (csvdt-line-end-p rope (cdr range))))))
        ranges))

(defun csvdt-picked (buffer)
  "Two values: BUFFER's banked lines and its selection, each a list of (START
. END) in order."
  (values (banked-spans buffer) (csvdt-selection-ranges buffer)))

;;; Running it

(define-record (csvdt-job (:include job) (:constructor make-csvdt-job) (:copier nil))
  "A run of csvdt over text of BUFFER, a job: PROGRAM run with ARGUMENTS, given
the INPUT of ROPE, the text as it was when the run began, and told to take
only the RANGES of it. Once it ends, EXIT, OUTPUT and SAID say how it ended
and what it wrote."
  (program nil :documentation "The csvdt program of CSVDT-JOB that is run.")
  (arguments nil :documentation "The arguments the program of CSVDT-JOB is run with, before its --lines.")
  (rope nil :documentation "The text of the buffer of CSVDT-JOB as it was when the run began.")
  (input nil :documentation "The (START . END) of the rope of CSVDT-JOB that is sent to csvdt: the buffer, or the part
of it the buffer is narrowed to.")
  (ranges nil
          :documentation "The list of (START . END) of the rope of CSVDT-JOB, whole lines, that csvdt is told to take
with --lines (CSVDT-SETTLE); NIL for all of the input.")
  (crlf nil :documentation "True when the lines of CSVDT-JOB end in carriage return and line feed (CRLF), which
are taken off before the text is sent.")
  (exit nil
        :documentation "How CSVDT-JOB ended: 0 when csvdt ended well, else what SANDBOX-RUN says (:FAILED, :TIMEOUT,
:UNAVAILABLE...).")
  (output nil :documentation "The octets csvdt wrote for CSVDT-JOB.")
  (said nil :documentation "What csvdt said on its error output for CSVDT-JOB, without its note on widening.")
  (snapped nil :documentation "True when the selection of CSVDT-JOB began or ended inside a line and was widened to
whole lines, for its report.")
  (widened nil :documentation "The lines csvdt took beyond those it was told to, in the form --lines reads, when it
widened them to whole records (a quoted field spanning lines), else NIL; for the report of CSVDT-JOB.")
  (cut nil :documentation "What the narrowing cuts of the lines of CSVDT-JOB, in words, or NIL.")
  (stretches nil :documentation "The number of stretches of text CSVDT-JOB covered, for its report.")
  (limit nil :documentation "The most octets the csvdt of CSVDT-JOB was let write (CSVDT-OUTPUT-LIMIT), once it
runs."))

(define-job-words csvdt-job
  :doing "Running csvdt"
  :description (format nil "Running csvdt ~{~a~^ ~}" (csvdt-job-arguments job))
  :verb "run csvdt"
  :left-words "csvdt was stopped, its output left out")

(defun csvdt-send (job fd)
  "Write JOB's ranges to the file descriptor (FD), csvdt's standard input,
a piece at a time: the whole input, ended by a newline, carriage returns before
newlines taken out where the buffer ends its lines with both. Stops when JOB
is asked to, or when csvdt stops reading."
  (let ((rope (csvdt-job-rope job))
        (piece (make-array *csvdt-piece* :element-type '(unsigned-byte 8)))
        (out (make-array *csvdt-piece* :element-type '(unsigned-byte 8)))
        (final nil))
    (flet ((put (octets end)
             (when (plusp end)
               (write-octets fd octets :end end :path "csvdt")
               (setf final (aref octets (1- end))))))
      (handler-case
          (let ((range (csvdt-job-input job)))
            (loop with at = (car range)
                  while (< at (cdr range))
                  do (when (car (csvdt-job-cancel job)) (return-from csvdt-send))
                     (let* ((n (min *csvdt-piece* (- (cdr range) at)))
                            (end (rope-copy-into rope at (+ at n) piece)))
                       (if (csvdt-job-crlf job)
                           (let ((kept 0))
                             (dotimes (i end)
                               (let ((octet (aref piece i)))
                                 (unless (and (= octet 13)
                                              (= 10 (if (< (1+ i) end)
                                                        (aref piece (1+ i))
                                                        (if (< (+ at n) (rope-octet-length rope))
                                                            (rope-octet rope (+ at n))
                                                            0))))
                                   (setf (aref out kept) octet)
                                   (incf kept))))
                             (put out kept))
                           (put piece end))
                       (incf at n)))
            ;; a last line with no newline is ended, as csvdt reads it with one
            (when (and final (/= final 10))
              (put (make-array 1 :element-type '(unsigned-byte 8) :initial-element 10) 1)))
        ;; csvdt ended without reading it all: what it said says why
        (file-system-error () nil)))))

(defparameter *csvdt-widening-note* "(?m)^csvdt: '--lines' widened to whole records, taking lines ([0-9,-]+)\\n?"
  "The regular expression for what csvdt says on its error output when --lines
took more lines than it was given. The group is every line it took, in the form
--lines reads.")

(defun csvdt-widening-note (said)
  "Two values: the lines csvdt's note in SAID, what it said on its error
output, says it took, or NIL when there is no note; and SAID without the
note."
  (multiple-value-bind (start end starts ends) (cl-ppcre:scan *csvdt-widening-note* said)
    (if start
        (values (subseq said (aref starts 0) (aref ends 0))
                (concatenate 'string (subseq said 0 start) (subseq said end)))
        (values nil said))))

(defun csvdt-run-arguments (job)
  "The arguments JOB runs csvdt with: its own, after the --lines naming the
lines it is to take, when it is to take only some."
  (let ((ranges (csvdt-job-ranges job)))
    (if ranges
        (list* "--lines" (csvdt-lines-argument (csvdt-job-rope job) (car (csvdt-job-input job)) ranges)
               (csvdt-job-arguments job))
        (csvdt-job-arguments job))))

(defun csvdt-output-limit (job)
  "The most octets JOB's csvdt may write: *CSVDT-OUTPUT-MULTIPLE* times its
input, at least *CSVDT-LEAST-OUTPUT-LIMIT*, and never more than the heap may
spare now (HEAP-BUDGET)."
  (let ((input (csvdt-job-input job)))
    (min (heap-budget)
         (max *csvdt-least-output-limit* (* *csvdt-output-multiple* (- (cdr input) (car input)))))))

(defun csvdt-work (job)
  "Run JOB's csvdt shut in (SANDBOX-RUN) over its input, written a piece at a
time (CSVDT-SEND) to a file of its own, which it reads on its standard input,
told to take the lines of JOB's ranges (CSVDT-RUN-ARGUMENTS). It is shown the
program alone, read only, and nothing else of yours; stopping the job ends
it, and so does writing more than CSVDT-OUTPUT-LIMIT, what it wrote then let
go."
  (let ((directory (new-private-directory (private-cache-directory "csvdt/") :hold nil))
        (program (csvdt-job-program job))
        (arguments (csvdt-run-arguments job))
        (limit (setf (csvdt-job-limit job) (csvdt-output-limit job))))
    (unwind-protect
         (let ((input (call-with-free-file directory "input" (lambda (fd path) (csvdt-send job fd) path))))
           (multiple-value-bind (written how said)
               (call-with-file input
                               (lambda (fd path size)
                                 (declare (ignore path size))
                                 (sandbox-run program arguments
                                              :input fd :directories (list program) :cancel (csvdt-job-cancel job)
                                              :seconds nil :memory nil :output-limit limit)))
             (if (car (csvdt-job-cancel job))
                 (setf (csvdt-job-status job) :stopped)
                 (multiple-value-bind (widened rest)
                     (csvdt-widening-note (string-trim '(#\Space #\Newline) (or said "")))
                   (setf (csvdt-job-output job) (if (eq how :too-much)
                                                    (make-array 0 :element-type '(unsigned-byte 8))
                                                    written)
                         (csvdt-job-widened job) widened
                         (csvdt-job-said job) (string-trim '(#\Space #\Newline) rest)
                         (csvdt-job-exit job) (if (eq how :done) 0 how)
                         (csvdt-job-status job) :done)))))
      (ignore-errors (delete-tree directory)))))

(defun csvdt-line-total (octets)
  "How many lines OCTETS hold, a last one with no newline counted."
  (+ (count 10 octets)
     (if (and (plusp (length octets)) (/= (aref octets (1- (length octets))) 10)) 1 0)))

(defun csvdt-fill-output (octets)
  "Make OCTETS, as csvdt wrote them, the whole of *csvdt output*, in
*CSVDT-OUTPUT-MODE*, point at its start; return the buffer. It stays a
buffer to edit and run csvdt on again, and undo brings back what it held
before. Lines banked in that are let go, the text they stood for being
gone."
  (let ((out (find-or-make-buffer *csvdt-output-name*)))
    (setf (buffer-banks out) nil
          (buffer-mark-active-p out) nil)
    (delete-spans out (list (cons 0 (buffer-size out))) :replacements (list octets))
    ;; entered after the text is in, so that csv-mode finds its separator in it
    (handler-case (set-major-mode out *csvdt-output-mode*)
      (error () (set-major-mode out 'fundamental-mode)))
    (setf (buffer-point out) 0)
    out))

(defun csvdt-strip-name (said)
  "SAID, what csvdt said, without the csvdt: it starts each of its lines with."
  (if (uiop:string-prefix-p "csvdt: " said) (subseq said (length "csvdt: ")) said))

(defmethod job-take-in ((job csvdt-job))
  "Show what JOB's csvdt wrote in *csvdt output* and say how the run went: how
many lines, over what, and what csvdt said besides; or, when it failed, its
ending and its reason, with what it wrote before failing shown too,
unless the run was over *csvdt output* itself, which keeps its text. A run
that wrote too much (CSVDT-OUTPUT-LIMIT) says so and shows nothing."
  (ecase (csvdt-job-status job)
    (:done
     (let ((output (csvdt-job-output job)) (said (csvdt-job-said job)) (source (csvdt-job-buffer job)))
       (if (eql (csvdt-job-exit job) 0)
           (progn
             (display-buffer (csvdt-fill-output output) :at :start)
             (message "~a"
                      (format nil
                              "csvdt~{ ~a~}: ~d line~:p~[~;~:;~:* from ~d stretches~]~
                               ~:[~;, selection widened to whole lines~]~
                               ~@[, widened to whole records: lines ~a~]~@[, ~a~]~@[~%~a~]"
                              (csvdt-job-arguments job) (csvdt-line-total output) (csvdt-job-stretches job)
                              (csvdt-job-snapped job) (csvdt-job-widened job) (csvdt-job-cut job)
                              (and (plusp (length said)) said))))
           (progn
             (unless (or (zerop (length output))
                         (and source (equal (buffer-name source) *csvdt-output-name*)))
               (display-buffer (csvdt-fill-output output) :at :start))
             (message "~a"
                      (if (eq (csvdt-job-exit job) :too-much)
                          (format nil "csvdt was ended: it wrote more than ~a, ~d times its input ~
                                       (*csvdt-output-multiple*) or ~a at least, and no more than a ~
                                       quarter of the memory free; nothing is shown"
                                  (octets-words (csvdt-job-limit job)) *csvdt-output-multiple*
                                  (octets-words *csvdt-least-output-limit*))
                          (format nil "csvdt ~a: ~a"
                                  (case (csvdt-job-exit job)
                                    (:failed "exited with an error")
                                    (:unavailable "could not run shut in")
                                    (t (format nil "ended: ~(~a~)" (csvdt-job-exit job))))
                                  (if (zerop (length said)) "(no message)" (csvdt-strip-name said)))))))))
    ((:stopped :failed) (message "~a" (job-ending-words job)))))

(defparameter *csvdt-version-needed* '(1 2 0)
  "The oldest csvdt this package runs, (MAJOR MINOR PATCH): the first that
reads --lines.")

(defun csvdt-check-version ()
  "An error saying so when the csvdt that runs is older than
*CSVDT-VERSION-NEEDED*. Its version is asked once for each program found
\(CSVDT-CACHED-VERSION); a version that cannot be read is let pass."
  (let* ((line (csvdt-cached-version))
         (found (multiple-value-bind (match groups) (cl-ppcre:scan-to-strings "(\\d+)\\.(\\d+)\\.(\\d+)" line)
                  (and match (map 'list #'parse-integer groups)))))
    (when (and found (loop for have in found for need in *csvdt-version-needed*
                           when (/= have need) return (< have need)))
      (error "csvdt is too old: ~a is ~a, and this package needs csvdt ~{~d~^.~} or later, which takes a selection: ~
              get a newer csvdt from github.com/YardQuit/csvdt"
             *csvdt-program* line *csvdt-version-needed*))))

(defun csvdt-run (buffer ranges arguments &key snapped)
  "Run csvdt with ARGUMENTS over BUFFER and show what it writes in *csvdt
output*. It is given all of the buffer, or of the part it is narrowed to, as
its input, and told to take only the lines of RANGES, each (START . END), by
--lines, which widens them to whole records where a quoted field spans lines
and says so; with no RANGES it takes all. SNAPPED says the selection began or
ended inside a line. The run goes on in the background when it takes more than
a moment."
  (let* ((directory (buffer-directory buffer))
         (files (csvdt-file-arguments arguments directory)))
    (csvdt-check-version)
    (when files
      (error "csvdt would read ~{~a~^, ~} and leave the selection out; ~
              these commands give it the lines on its standard input"
             files))
    (when (running-job buffer 'csvdt-job)
      (error "~a" (substitute-command-keys "csvdt is still running over this buffer: \\[stop-job] stops it")))
    (let* ((rope (buffer-text buffer))
           (input (cons (buffer-start buffer) (buffer-end buffer))))
      (multiple-value-bind (lines widened) (csvdt-settle rope input ranges)
        (when (and ranges (null lines))
          (error "Nothing to run csvdt on: the selection lies outside the part of the buffer narrowed to"))
        (let* ((whole (or (null lines) (equal lines (list input))))
               (job (make-csvdt-job :buffer buffer :program (csvdt-program) :arguments arguments :rope rope
                                    :input input :ranges (unless whole lines)
                                    :crlf (buffer-crlf-p buffer) :snapped (or snapped widened)
                                    :cut (csvdt-cut-note rope input (or lines (list input)))
                                    :stretches (if whole 1 (length lines)))))
          (start-job-thread job #'csvdt-work :name "tuatara csvdt" :details (format nil "~{~a~^ ~}" arguments))
          (take-in-soon job *csvdt-wait* "Running csvdt"))))))

;;; The commands

(define-command csvdt-run-buffer ()
  "Run csvdt over the whole buffer with arguments read in the minibuffer
\(\\[csvdt-run-dwim] says how they are read); show what it writes in *csvdt
output*."
  (let ((b (current-buffer)))
    (csvdt-run b nil (csvdt-read-arguments))))

(define-command csvdt-run-region ()
  "Run csvdt over the lines of the selection with arguments read in the
minibuffer: to try something on a few rows before the whole file. A
selection starting or ending inside a line takes the whole line, and a
rectangle the whole rows it spans. csvdt is given the whole buffer and the
lines selected, so it takes the header from the top and widens the lines to
whole records."
  (let* ((b (current-buffer)) (selection (csvdt-selection-ranges b)))
    (unless selection (error "No selection"))
    (csvdt-run b selection (csvdt-read-arguments)
               :snapped (csvdt-mid-line-p (buffer-text b) selection))))

(define-command csvdt-run-banked ()
  "Run csvdt over the banked lines (\\[bank-lines]) with arguments
read in the minibuffer:
the output following the buffer's order. csvdt is given the whole buffer, so
a duration is measured from the row before, banked or not. The lines stay
banked."
  (let* ((b (current-buffer)) (banked (banked-spans b)))
    (unless banked (error "~a" (substitute-command-keys "No banked lines: \\[bank-lines] banks them")))
    (csvdt-run b banked (csvdt-read-arguments))))

(define-command csvdt-run-dwim ()
  "Run csvdt over the banked lines and the selection together, or with
neither over the whole buffer; show what it writes in *csvdt output*. Both,
not one or the other: the selection is most often the part not banked yet.
Where they meet or overlap a line is sent once.
The arguments are read in the minibuffer, *CSVDT-DEFAULT-ARGUMENTS*
selected: typing replaces them, \\<minibuffer>\\[minibuffer-forward-char]
keeps them to add to, \\[minibuffer-finish] runs them;
\\[minibuffer-complete] completes an option from those csvdt reports, and
\\[minibuffer-previous-history] brings back a line run before. They are split
as a shell splits them, a comma staying inside its argument. A filename among
them is refused: the lines go to csvdt on its standard input, and a file
would take their place. \\[csvdt-describe-run] says what a run would cover,
without running."
  (let ((b (current-buffer)))
    (multiple-value-bind (banked selection) (csvdt-picked b)
      (csvdt-run b (append banked selection) (csvdt-read-arguments)
                 :snapped (and selection (csvdt-mid-line-p (buffer-text b) selection))))))

(defun csvdt-describe-ranges (buffer ranges)
  "RANGES of BUFFER in words: 3 lines in 2 stretches."
  (let ((lines (span-line-count buffer ranges)))
    (format nil "~d line~:p in ~d stretch~:*~[es~;~:;es~]" lines (length ranges))))

(define-command csvdt-describe-run ()
  "Say what \\[csvdt-run-dwim] would cover, and from what, without running
anything: for when a run covered more or less than expected. Counted in whole
lines, as they go to csvdt with --lines; csvdt widens them to whole records
where a quoted field spans lines, and the run says which lines it took."
  (let* ((b (current-buffer))
         (rope (buffer-text b))
         (input (cons (buffer-start b) (buffer-end b))))
    (multiple-value-bind (banked selection) (csvdt-picked b)
      (flet ((settle (ranges) (and ranges (values (csvdt-settle rope input ranges)))))
        (let ((all (settle (append banked selection))) (banked (settle banked)) (selection (settle selection)))
          (message "~a"
                   (format nil "csvdt would run over ~a.  Banked: ~a.  Selection: ~a."
                           (if all
                               (csvdt-describe-ranges b all)
                               (format nil "the whole buffer, ~d line~:p" (span-line-count b (list input))))
                           (if banked (csvdt-describe-ranges b banked) "none")
                           (if selection (csvdt-describe-ranges b selection) "none"))))))))

(define-command csvdt-help ()
  "Show csvdt's own --help, read from the program each time, so that it is
always that of the csvdt that runs."
  (show-help-pieces (ansi-pieces (csvdt-help-text)) :name "*csvdt help*"))

(define-command csvdt-version ()
  "Say which csvdt runs, and which time zone database is built into it."
  (message "~a" (csvdt-version-string)))

;;; Keys

(defun install-csvdt ()
  "Bind the csvdt commands in CSV and tab-separated values (TSV) buffers under
\\`C-c v': r \\[csvdt-run-dwim], b the buffer, SPC the selection, k the banked
lines, ? \\[csvdt-describe-run], h the help, v the version."
  (define-keys (mode-keymap 'csv-mode)
               '(("C-c v r" csvdt-run-dwim) ("C-c v b" csvdt-run-buffer) ("C-c v SPC" csvdt-run-region)
                 ("C-c v k" csvdt-run-banked) ("C-c v ?" csvdt-describe-run) ("C-c v h" csvdt-help)
                 ("C-c v v" csvdt-version)))
  (label-keys (mode-keymap 'csv-mode) '(("C-c v" "csvdt"))))

(install-csvdt)
