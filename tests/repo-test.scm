;; Run from the repository root with: steel tests/repo-test.scm
;; SPDX-License-Identifier: MIT OR Apache-2.0

(require "../src/repo.scm")

(define failures 0)

(define (check name actual expected)
  (unless (equal? actual expected)
    (set! failures (+ failures 1))
    (displayln "FAIL " name ": expected " expected ", got " actual)))

(define backslash (string (integer->char 92)))

(check "split unix path" (split-path "/a/b/c.txt") '("/a/b" "c.txt"))
(check "split windows path"
       (split-path (string-append "D:" backslash "a" backslash "c.txt"))
       (list (string-append "D:" backslash "a") "c.txt"))
(check "no directory" (split-path "c.txt") #false)

(define root (current-directory))
(check "git dir from root" (find-git-dir root) (string-append root "/.git"))
(check "git dir from subdir" (find-git-dir (string-append root "/src")) (string-append root "/.git"))

(define stamp (head-stamp (find-git-dir root)))
(check "stamp is stable" (head-stamp (find-git-dir root)) stamp)
(check "stamp sees HEAD" (not (equal? (car stamp) #false)) #true)

(if (= failures 0)
    (displayln "ok")
    (error "repo-test failed:" failures))
