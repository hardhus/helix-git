;; Finding a file's git directory and noticing when HEAD may have moved,
;; using only the filesystem (no git process).
;; SPDX-License-Identifier: MIT OR Apache-2.0

(provide split-path
         find-git-dir
         head-stamp)

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

(define (mtime path)
  (with-handler (lambda (_) #false) (fs-metadata-modified (file-metadata path))))

;; Changes whenever HEAD moves: a checkout rewrites HEAD, a commit, reset or
;; rebase appends to the HEAD reflog, and nearly all of them write the index.
;; While the stamp is unchanged, a cached HEAD blob id is still valid.
(define (head-stamp git-dir)
  (list (mtime (string-append git-dir "/HEAD"))
        (mtime (string-append git-dir "/logs/HEAD"))
        (mtime (string-append git-dir "/index"))))
