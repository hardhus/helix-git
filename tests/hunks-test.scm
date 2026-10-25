;; Run with: steel tests/hunks-test.scm
;; SPDX-License-Identifier: MIT OR Apache-2.0

(require "../src/hunks.scm")

(define failures 0)

(define (check name actual expected)
  (unless (equal? actual expected)
    (set! failures (+ failures 1))
    (displayln "FAIL " name ": expected " expected ", got " actual)))

(define (span h)
  (list (hunk-old-start h) (hunk-old-count h) (hunk-new-start h) (hunk-new-count h)))

(define diff-text
  (string-append "diff --git a/x b/-\n"
                 "--- a/x\n"
                 "+++ b/-\n"
                 "@@ -0,0 +1,2 @@\n"
                 "+new 1\r\n"
                 "+new 2\n"
                 "@@ -3,2 +4,0 @@ context\n"
                 "-gone 1\n"
                 "--- gone 2\n"
                 "@@ -8 +7 @@\n"
                 "-old\n"
                 "+new\n"
                 "\\ No newline at end of file\n"
                 "@@ -10,2 +8,0 @@\n"
                 "-tail 1\n"
                 "-tail 2\n"))

(define hunks (parse-hunks diff-text))

(check "count" (length hunks) 4)
(check "insertion at top" (span (list-ref hunks 0)) '(0 0 0 2))
(check "pure removal" (span (list-ref hunks 1)) '(2 2 4 0))
(check "change" (span (list-ref hunks 2)) '(7 1 6 1))
(check "removal at end" (span (list-ref hunks 3)) '(9 2 8 0))
(check "lines keep prefix, drop CR" (hunk-lines (list-ref hunks 0)) '("+new 1" "+new 2"))
(check "body line that looks like a header" (hunk-lines (list-ref hunks 1)) '("-gone 1" "--- gone 2"))
(check "no-newline marker skipped" (hunk-lines (list-ref hunks 2)) '("-old" "+new"))

;; Buffer has 8 lines (0..7).
(check "inside insertion" (span (hunk-at hunks 1 7)) '(0 0 0 2))
(check "removal marker line" (span (hunk-at hunks 4 7)) '(2 2 4 0))
(check "line without change" (hunk-at hunks 5 7) #false)
(check "removed at end -> last line" (span (hunk-at hunks 7 7)) '(9 2 8 0))
(check "empty diff" (parse-hunks "") '())

(check "base range in hunk" (base-range-for hunks 6 7) '(7 1))
(check "base range shifted" (base-range-for hunks 5 7) '(5 0))
(check "base range above all hunks" (base-range-for (list (list-ref hunks 2)) 3 7) '(3 0))

(if (= failures 0)
    (displayln "ok")
    (error "hunks-test failed:" failures))
