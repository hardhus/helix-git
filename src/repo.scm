;; Finding a file's git directory and the commit HEAD points to, using only
;; the filesystem (no git process).
;; SPDX-License-Identifier: MIT OR Apache-2.0

(provide split-path
         find-git-dir
         head-commit)

(define backslash (integer->char 92))

;; "D:\a\b.txt" or "/a/b.txt" -> ("D:\a" "b.txt"), or #false without a directory.
(define (split-path path)
  (let loop ([i (- (string-length path) 1)])
    (cond
      [(< i 0) #false]
      [(or (char=? (string-ref path i) #\/) (char=? (string-ref path i) backslash))
       (list (substring path 0 i) (substring path (+ i 1) (string-length path)))]
      [else (loop (- i 1))])))

(define (first-line text)
  (let ([lines (split-many text "\n")])
    (if (empty? lines) "" (trim (car lines)))))

(define (absolute? path)
  (or (starts-with? path "/")
      (starts-with? path (string backslash))
      (and (> (string-length path) 1) (char=? (string-ref path 1) #\:))))

;; A linked worktree or submodule has a `.git` file: "gitdir: <path>".
(define (read-gitdir-file dir file)
  (let* ([port (open-input-file file)]
         [line (first-line (read-port-to-string port))])
    (close-port port)
    (if (starts-with? line "gitdir:")
        (let ([target (trim (substring line 7 (string-length line)))])
          (if (absolute? target) target (string-append dir "/" target)))
        #false)))

;; The git directory for files in `dir`, or #false. Walks up like git does.
(define (find-git-dir dir)
  (let loop ([dir dir] [depth 0])
    (let ([candidate (string-append dir "/.git")])
      (cond
        [(> depth 64) #false]
        [(is-dir? candidate) candidate]
        [(is-file? candidate) (with-handler (lambda (_) #false) (read-gitdir-file dir candidate))]
        [else
         (let ([parent (split-path dir)])
           (if (and parent (not (equal? (car parent) "")) (not (equal? (car parent) dir)))
               (loop (car parent) (+ depth 1))
               #false))]))))

(define (read-text path)
  (with-handler (lambda (_) #false)
                (let* ([port (open-input-file path)]
                       [text (read-port-to-string port)])
                  (close-port port)
                  text)))

;; A linked worktree keeps its own HEAD but shares refs with the main
;; repository, named in its `commondir` file.
(define (common-dir git-dir)
  (let ([text (read-text (string-append git-dir "/commondir"))])
    (if text
        (let ([dir (first-line text)])
          (if (absolute? dir) dir (string-append git-dir "/" dir)))
        git-dir)))

;; "<oid> <ref>" lines of packed-refs; refs that were never updated since a
;; `git gc` live only here.
(define (packed-ref common ref)
  (let ([text (read-text (string-append common "/packed-refs"))]
        [suffix (string-append " " ref)])
    (and text
         (let loop ([lines (split-many text "\n")])
           (cond
             [(empty? lines) #false]
             [(ends-with? (trim (car lines)) suffix) (car (split-many (trim (car lines)) " "))]
             [else
              (let ([rest (cdr lines)])
                (loop rest))])))))

;; The commit HEAD points to, or #false (unborn branch, unreadable repo).
(define (head-commit git-dir)
  (let ([head (read-text (string-append git-dir "/HEAD"))])
    (and head
         (let ([line (first-line head)])
           (if (starts-with? line "ref:")
               (let* ([ref (trim (substring line 4 (string-length line)))]
                      [common (common-dir git-dir)]
                      [direct (or (read-text (string-append git-dir "/" ref))
                                  (read-text (string-append common "/" ref)))])
                 (if direct (first-line direct) (packed-ref common ref)))
               line)))))
