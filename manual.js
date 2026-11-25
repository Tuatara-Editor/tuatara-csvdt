window.tuataraManualText = {"01-what-the-csvdt-package-is":" what the csvdt package is the package that runs the csvdt program over the records of a csv buffer. csvdt converts the timestamps and durations in the records of a csv file. the package hands it the buffer, in the background, and shows what csvdt writes in a buffer of its own, *csvdt output* . the buffer is never changed. csvdt is a program of its own, installed apart from tuatara. the package needs csvdt 1.2.0 or later, which takes a selection itself; an older one is refused with a message saying so. its options and what they do are in its own help; c-c v h shows it. this manual covers what the package adds: which lines a run covers, how the arguments are typed, and what happens to the result.","01-what-the-csvdt-package-is#the-keys":"1.1 the keys in a csv or tsv (tab-separated values) buffer, the keys are under c-c v . tuatara labels the prefix csvdt in its key help. key command what it runs csvdt over c-c v r csvdt-run-dwim banked lines and selection, else all c-c v b csvdt-run-buffer the whole buffer c-c v spc csvdt-run-region the selection c-c v k csvdt-run-banked the banked lines c-c v ? csvdt-describe-run nothing: says what a run would cover c-c v h csvdt-help nothing: shows csvdt's --help c-c v v csvdt-version nothing: says which csvdt runs in any other buffer the commands are run with m-x , or from a key of your own in the init file: (bind-key \"; c\" 'csvdt-run-dwim :map :leader) ; spc ; c","01-what-the-csvdt-package-is#if-csvdt-is-not-found":"1.2 if csvdt is not found m-x check-health says whether tuatara finds csvdt. when it does not, chapter 5 says how to name its path. c-c v v says which csvdt runs; the version is asked once for each program found, not at each run.","02-what-gets-processed":" what gets processed which lines a run covers, and what csvdt takes of them. csvdt-run-dwim takes the banked lines and the selection together, merged so a line in both goes once. with neither, it takes the whole buffer. banked lines are tuatara's own ( bank-lines , m l in normal state). csvdt writes them in buffer order, whatever order they were banked in. running over them leaves them banked. the selection is taken as y and d take it: a line selection whole, a rectangle by the rows it spans. a rectangle's columns are ignored, because picking columns is csvdt's job ( --remove , -a ). a run takes the main selection only, not the places of several cursors or of a split. csvdt-describe-run says what a run would cover, without running it. it has no line of arguments to read. it counts whole lines, as they go to csvdt, and says nothing of the widening csvdt does to reach whole records.","02-what-gets-processed#what-csvdt-is-given":"2.1 what csvdt is given csvdt is given the whole buffer, or the part it is narrowed to, as its input file. a run over the whole buffer says nothing more. a run over banked lines or a selection adds --lines with the lines picked, counted from 1 at the start of the input, as in --lines 3-5,9,20-22 . csvdt reads the input as it reads any file and keeps every record that touches a selected line, whole, in input order, each once. the output is what a run over the whole buffer writes for those records. the package reads nothing of the text as csv. so csvdt decides where a record begins, which lines are comments ( --comment ) and which record is the header. under -h -p the header is the buffer's first record and is printed once at the top, whether or not it was selected. with a selection or banked lines, a duration ( -d with one column) is measured from the row before the first one taken, taken or not. a selection that starts or ends inside a line takes the whole line. the run says , selection widened to whole lines . a quoted field can hold a line end, so a record is not always a line. when csvdt takes lines the selection did not name, the run says , widened to whole records: lines 2-3 , naming every line it took. a narrowing that begins or ends inside a line hands csvdt that line in part. the run says , first line cut short by the narrowing (or the last, or both). a narrowing that cuts a quoted field at a line end is csvdt's to report. a selection of only comment or blank lines gives an empty result, and csvdt says so.","02-what-gets-processed#the-bytes":"2.2 the bytes the buffer's bytes go to csvdt as they are. a file that is not utf-8 reaches csvdt as it is on disk, and csvdt refuses it in its own words. line ends are sent as \\n when the buffer's are \\r\\n .","03-arguments":" arguments the line of csvdt options a run asks for. a run asks for csvdt's arguments in the minibuffer, as a line the way a shell takes one. the line starts as *csvdt-default-arguments* , which is -h -p , and is left selected. c-c v v says which csvdt will run. its options are asked for in the background while you type, for completion. key what it does type anything replaces the prefill right or c-f keeps it, to add to ret runs it as it stands tab completes the option before the cursor m-p and m-n back and forth through lines run before the prefill is selected, not only offered, because leaving -h off a file with a header is loud, while passing it to a file without one is quiet. the first row is then taken for a header and goes through unconverted.","03-arguments#how-the-line-is-split":"3.1 how the line is split the line is split as a shell splits it, and not on commas, because a comma is csvdt's own separator inside a value ( -a 1,0 , -i 0,replace ). either kind of quote works. double quotes take \\t , \\n , \\r , \\\\ and \\\" . any other backslash is refused, so \"c:\\data\" is refused rather than misread. single quotes take everything as it is. outside quotes a backslash is itself. nothing is run through a shell.","03-arguments#file-names":"3.2 file names a file name in the line is refused. these commands give csvdt the lines on its standard input, and a named file would take their place in a result that looks exactly like a run over them. only a name that is a file on disk is refused. which arguments are values and which are file names comes from csvdt --list-options , so -u 0 with a file called 0 lying about is still a run.","03-arguments#what-csvdt-reports":"3.3 what csvdt reports the help is csvdt's own --help , read from the program each time. the options offered for completion come from csvdt --list-options . the package keeps them against the program's real path and the time it was written, so a rebuilt csvdt is asked again and an unchanged one is not run just to find that out. a csvdt too old to list its options has them read from --help instead. nothing in the package needs updating when csvdt changes. only one option is named, --lines , which tells csvdt which lines a run over part of a buffer means. the tests hold it to an option csvdt still reports, and fail if any other option csvdt reports is named in the package.","04-running-and-the-output":" running, and the output what happens while csvdt runs, and where the result goes.","04-running-and-the-output#a-run-is-a-job":"4.1 a run is a job a quick run looks instant. one that takes more than half a second carries on in the background with the editor free. the letter p is lit in the mode line, c-x j lists the job, and c-x j ( m-x stop-job ) ends csvdt. a second run over the same buffer while one is going is refused, not queued. csvdt runs shut in by the sandbox ( bwrap ): it reads the lines on its standard input and sees the system's programs and libraries, and itself, read only, and nothing else of yours. without the sandbox it does not run, and the echo area says why.","04-running-and-the-output#the-output-buffer":"4.2 the output buffer the output goes to *csvdt output* , in the major mode *csvdt-output-mode* names, csv-mode by default. when that mode cannot be entered the buffer is left in fundamental-mode , so a result csvdt has made is not lost. the buffer is one to edit. sort its lines, or run csvdt on it again to feed a result back through. lines banked in the previous result are let go, because the text they stood for is gone.","04-running-and-the-output#how-much-csvdt-may-write":"4.3 how much csvdt may write what csvdt writes is held in the editor's memory until it is in the buffer, so a run may write at most *csvdt-output-multiple* times its input, eight by default, and never less than 64 mb. whatever those say, it may never write more than a quarter of the editor's free memory as the run starts. most runs write about as much as they read. some options write far more: -f=widest pads every record to the widest one, so a file with one very wide record and many short ones grows many times over. a run that writes more than its limit is ended, nothing of it is shown, and the echo area says so: csvdt was ended: it wrote more than 64.0 mb, 8 times its input (*csvdt-output-multiple*) or 64.0 mb at least, and no more than a quarter of the memory free; nothing is shown raise *csvdt-output-multiple* for such a run when the computer has the memory for it (chapter 5). the quarter of free memory is not a setting: a run that reaches it would leave the editor too little to go on.","04-running-and-the-output#the-echo-area":"4.4 the echo area the source buffer is never changed. on success the echo area gives the line count, the stretches when there was more than one, the widening notes of chapter 2, and anything csvdt said on stderr about a run that still succeeded: csvdt -h -p -u0 -i 0,replace: 3 lines from 2 stretches on failure it gives csvdt's own reason and how it ended. what csvdt wrote before failing is shown in *csvdt output* , except when the run was fed from that buffer, whose text is kept: csvdt exited with an error: '--utc' was given \"0-i\", which is not a column number.","05-settings-and-the-csvdt-program":" settings and the csvdt program the package's settings, and how to point it at a csvdt that is not on the path. each setting has its help in c-h v . chapter 6 lists them with their defaults. set them in the init file, after :config of load-package .","05-settings-and-the-csvdt-program#the-csvdt-program":"5.1 the csvdt program *csvdt-program* is a name, looked for on the path, or a full path from / or ~ . a full path is the file that is run, and it is never looked for on the path. a relative path such as \"./target/release/csvdt\" is refused, because it would run whatever file of that name stands beside the csv file. (load-package \"csvdt\" :source \"https://github.com/tuatara-editor/tuatara-csvdt\" :config (setf *csvdt-program* \"~/src/csvdt/target/release/csvdt\"))","05-settings-and-the-csvdt-program#the-arguments":"5.2 the arguments *csvdt-default-arguments* is the text the argument line starts with. the default, -h -p , suits a file with a header row, the header printed. use \"\" for none.","05-settings-and-the-csvdt-program#obsolete-settings":"5.3 obsolete settings five settings fed the package's own reading of the buffer as csv, which csvdt now does itself (chapter 2). they are obsolete: they do nothing, and are removed in the next major version. setting one is harmless. *csvdt-region-carries-header* : whether the buffer's header went in front of a selection. csvdt always takes the buffer's first record for the header now. *csvdt-header-options* , *csvdt-single-quote-options* , *csvdt-read-delimiter-options* and *csvdt-comment-options* : the names of the options saying the first record is a header, making ' the quote character, setting the delimiter fields are read with, and naming a comment character. a run over part of a buffer under =--comment is no longer refused.","05-settings-and-the-csvdt-program#the-output-mode":"5.4 the output mode *csvdt-output-mode* is the major mode of *csvdt output* . see chapter 4.","05-settings-and-the-csvdt-program#how-much-csvdt-may-write":"5.5 how much csvdt may write *csvdt-output-multiple* is how much csvdt may write for a run, as a multiple of its input: 8 by default, and never less than 64 mb, nor more than a quarter of the editor's free memory. a run that writes more is ended. see chapter 4. (load-package \"csvdt\" :source \"https://github.com/tuatara-editor/tuatara-csvdt\" :config (setf *csvdt-output-multiple* 32))","05-settings-and-the-csvdt-program#tests":"5.6 tests tools/test.sh in the package runs its tests. the runs of csvdt need a program to run: csvdt=/path/to/csvdt names it, else the one on the path is used. without one those tests are skipped, not passed.","06-every-command-and-setting":" every command and setting each command and setting of the csvdt package, to look one up by name. the tables are made from the program each time this manual is made, so they never list a command or setting that the package does not have. the first table has four columns. the first two are keys: the modal keys, which work only with modal editing on, and the non-modal keys, which work with it off too. a command with no key says m-x and its name in the second column, because you can only run it by its name. the third column is the name of the command and the fourth says what it does. to run a command by its name, press m-x , type a few letters of the name and press ret . to find a command from within the editor, press c-h f . to find the command that a key runs, press c-h k and then the key. the editor's own settings and commands are in chapters 21 and 22 of its manual.","06-every-command-and-setting#every-command":"6.1 every command modal non-modal command what it does none c-c v ? csvdt-describe-run say what m-x csvdt-run-dwim would cover, and from what, without running anything: for when a run covered more or less than expected. none c-c v h csvdt-help show csvdt's own –help, read from the program each time, so that it is always that of the csvdt that runs. none c-c v k csvdt-run-banked run csvdt over the banked lines (c-z m l) with arguments read in the minibuffer: the output following the buffer's order. none c-c v b csvdt-run-buffer run csvdt over the whole buffer with arguments read in the minibuffer (m-x csvdt-run-dwim says how they are read); show what it writes in csvdt output . none c-c v r csvdt-run-dwim run csvdt over the banked lines and the selection together, or with neither over the whole buffer; show what it writes in csvdt output . none c-c v spc csvdt-run-region run csvdt over the lines of the selection with arguments read in the minibuffer: to try something on a few rows before the whole file. none c-c v v csvdt-version say which csvdt runs, and which time zone database is built into it.","06-every-command-and-setting#every-setting":"6.2 every setting setting default values what it changes *csvdt-comment-options* (\"--comment\") a list, each text obsolete: no longer read, and removed in the next major version. *csvdt-default-arguments* \"-h -p\" text the arguments a csvdt command line starts with, selected. *csvdt-header-options* (\"-h\" \"--has-header\") a list, each text obsolete: no longer read, and removed in the next major version. *csvdt-output-mode* csv-mode a function the major mode of csvdt output . *csvdt-output-multiple* 8 a whole number, 1 or more how much csvdt may write for a run, as a multiple of what it is given: eight times its input by default, and never less than csvdt-least-output-limit , nor more than a quarter of the editor's free memory when the run starts. *csvdt-program* \"csvdt\" text the csvdt program to run. *csvdt-read-delimiter-options* (\"--read-delimiter\") a list, each text obsolete: no longer read, and removed in the next major version. *csvdt-region-carries-header* t t, nil obsolete: no longer read, and removed in the next major version. *csvdt-single-quote-options* (\"--single-quote\") a list, each text obsolete: no longer read, and removed in the next major version."};
// The manual's pages: filter the contents column to the headings whose title or
// text holds what is typed in its box, and change between light and dark
// colours (the choice kept in this browser for the next page). The entry for
// the part being read is marked as the page scrolls. The text of
// every section comes before this script, in window.tuataraManualText, made
// when the manual is built. Links are left alone. No address is ever loaded.
(function () {
  var root = document.documentElement;
  var key = "tuatara-manual-theme";
  var saved = null;
  try { saved = window.localStorage.getItem(key); } catch (e) { saved = null; }
  if (saved === "light" || saved === "dark") { root.setAttribute("data-theme", saved); }

  function dark() {
    var chosen = root.getAttribute("data-theme");
    if (chosen) { return chosen === "dark"; }
    return Boolean(window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches);
  }

  var button = document.querySelector("button.theme");
  if (button) {
    var label = function () {
      button.textContent = dark() ? "Light" : "Dark";
      button.setAttribute("aria-label", dark() ? "Use light colours" : "Use dark colours");
    };
    button.hidden = false;
    label();
    button.addEventListener("click", function () {
      var next = dark() ? "light" : "dark";
      root.setAttribute("data-theme", next);
      try { window.localStorage.setItem(key, next); } catch (e) { /* kept for this page only */ }
      label();
    });
  }

  var nav = document.querySelector("nav.toc");
  var box = nav && nav.querySelector("input");
  if (!box) { return; }
  var texts = window.tuataraManualText || {};

  // The key of a section in the text: a chapter's page name without its
  // ending, then # and the heading's id. On the page of every chapter the
  // links are "10-directories.html#marks", on the whole manual "#10-directories--marks".
  function keyOf(href) {
    var parts = /^#?([0-9]+-[^#.]*?)(?:\.html)?(?:(?:#|--)(.*))?$/.exec(href || "");
    if (!parts) { return null; }
    return parts[2] ? parts[1] + "#" + parts[2] : parts[1];
  }

  // Show ITEM when its title or text holds WORDS, or any entry under it does.
  function show(item, words) {
    var link = item.querySelector(":scope > a");
    var title = link ? link.textContent.toLowerCase() : "";
    var text = (link && texts[keyOf(link.getAttribute("href"))]) || "";
    var hit = words === "" || title.indexOf(words) !== -1 || text.indexOf(words) !== -1;
    item.querySelectorAll(":scope > ol > li").forEach(function (inner) {
      if (show(inner, words)) { hit = true; }
    });
    item.classList.toggle("hidden", !hit);
    return hit;
  }

  box.addEventListener("input", function () {
    var words = box.value.trim().toLowerCase().replace(/\s+/g, " ");
    nav.classList.toggle("filtering", words !== "");
    nav.querySelectorAll("ol.chapters > li").forEach(function (item) { show(item, words); });
  });

  // The entry of the column for the part being read is marked, following as
  // the page is scrolled: the last heading that has reached the middle of
  // the window, and the entries it is under, so a section folded out of sight
  // leaves the section holding it marked. On the whole manual, where no chapter is marked as the one
  // shown, its chapter is unfolded too.
  var whole = !nav.querySelector("li.here");
  var here = location.pathname;
  var marks = [];
  nav.querySelectorAll("ol.chapters a").forEach(function (link) {
    var url = new URL(link.href, location.href);
    if (url.pathname !== here) { return; }
    var target = url.hash ? document.getElementById(decodeURIComponent(url.hash.slice(1)))
                          : document.querySelector("main h1");
    if (target) { marks.push({ link: link, target: target, top: 0 }); }
  });
  if (marks.length === 0) { return; }
  var marked = null;

  function measure() {
    marks.forEach(function (mark) { mark.top = mark.target.getBoundingClientRect().top + window.scrollY; });
    marks.sort(function (a, b) { return a.top - b.top; });
  }

  // Mark or unmark the entry of MARK and every entry it is under.
  function light(mark, on) {
    for (var item = mark.link.closest("li"); item && nav.contains(item); item = item.parentElement.closest("li")) {
      item.querySelector(":scope > a").classList.toggle("in-view", on);
    }
  }

  // Keep LINK in view in whichever part of the column scrolls.
  function reveal(link) {
    [nav, nav.querySelector("ol.chapters")].forEach(function (box) {
      if (!box || box.scrollHeight <= box.clientHeight) { return; }
      var outer = box.getBoundingClientRect();
      var inner = link.getBoundingClientRect();
      if (inner.top < outer.top) { box.scrollTop -= outer.top - inner.top + 24; }
      else if (inner.bottom > outer.bottom) { box.scrollTop += inner.bottom - outer.bottom + 24; }
    });
  }

  // Mark the entry of the last heading at or above the middle of the
  // window, the first when none is: a search in the measured places, the
  // page changed only when the entry is another.
  function follow() {
    var line = window.scrollY + window.innerHeight / 2;
    var low = 0, high = marks.length - 1, found = marks[0];
    while (low <= high) {
      var middle = (low + high) >> 1;
      if (marks[middle].top <= line) { found = marks[middle]; low = middle + 1; } else { high = middle - 1; }
    }
    if (found === marked) { return; }
    if (marked) { light(marked, false); }
    marked = found;
    light(marked, true);
    if (whole) {
      var chapter = marked.link.closest("ol.chapters > li");
      nav.querySelectorAll("ol.chapters > li.here").forEach(function (item) {
        if (item !== chapter) { item.classList.remove("here"); }
      });
      if (chapter) { chapter.classList.add("here"); }
    }
    reveal(marked.link);
  }

  // Measure again when pictures have loaded or the window changed size.
  function again() {
    measure();
    if (marked) { light(marked, false); }
    marked = null;
    follow();
  }

  measure();
  follow();
  window.addEventListener("scroll", follow, { passive: true });
  window.addEventListener("resize", again);
  window.addEventListener("load", again);
}());
