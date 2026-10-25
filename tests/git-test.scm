;; Run from the repository root with: steel tests/git-test.scm
;; Needs git on PATH and a checkout of this repository.
;; SPDX-License-Identifier: MIT OR Apache-2.0

(require "../src/git.scm")
(require "../src/hunks.scm")

(define failures 0)

(define (check name ok?)
  (unless ok?
    (set! failures (+ failures 1))
    (displayln "FAIL " name)))

(define dir (current-directory))

(define base (head-base dir "cog.scm"))
(check "cog.scm is in HEAD" (Ok? base))

(define base-text (read-file (Ok->value base)))
(check "cached copy has content" (string-contains? base-text "package-name"))
(check "second lookup hits the cache" (equal? (head-base dir "cog.scm") base))

(check "unknown file is not in HEAD" (equal? (head-base dir "no-such-file") (Err 'not-in-head)))

(define unchanged (diff-against dir (Ok->value base) base-text))
(check "same text -> no hunks" (empty? (parse-hunks (Ok->value unchanged))))

(define changed (diff-against dir (Ok->value base) (string-append "added line\n" base-text)))
(define hunks (parse-hunks (Ok->value changed)))
(check "one inserted line" (and (= (length hunks) 1) (equal? (hunk-lines (car hunks)) '("+added line"))))

(if (= failures 0)
    (displayln "ok")
    (error "git-test failed:" failures))
