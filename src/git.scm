;; Running git: the HEAD version of a file, and diffing a buffer against it.
;; SPDX-License-Identifier: MIT OR Apache-2.0
;;
;; Everything here blocks on child processes, so call it from a background
;; thread (see `spawn-native-thread`), never from the editor thread.

(require-builtin steel/process)

(provide git-run
         blob-id
         base-file
         head-base
         read-file
         diff-against)

;; Run git in `dir` and return (Ok stdout) or (Err message). `input`, when
;; given, is written to git's stdin. stderr is piped so git never writes
;; over the editor's screen.
(define (git-run dir args [input #false])
  (let ([cmd (command "git" args)])
    (set-current-dir! cmd dir)
    (with-stdout-piped cmd)
    (with-stderr-piped cmd)
    (when input
      (with-stdin-piped cmd))
    (let ([spawned (spawn-process cmd)])
      (if (Err? spawned)
          (Err "could not run git (is it on your PATH?)")
          (let ([child (Ok->value spawned)])
            (when input
              (let ([port (child-stdin child)])
                (write-string input port)
                (close-port port)))
            (wait->stdout child))))))

(define (env-or name default)
  (with-handler (lambda (_) default) (env-var name)))

;; Base versions are cached on disk by blob id, so a file's HEAD content is
;; fetched from git only once per commit that changed it. The cache never
;; goes stale: a different HEAD content has a different blob id.
(define (cache-dir)
  (string-append (env-or "TEMP" (env-or "TMPDIR" "/tmp")) "/helix-git"))

(define (read-file path)
  (let* ([port (open-input-file path)]
         [text (read-port-to-string port)])
    (close-port port)
    text))

(define (write-file! path text)
  (let ([port (open-output-file path)])
    (write-string text port)
    (close-port port)))

;; The blob id of `name` (a file name inside `dir`) in HEAD.
;; Returns (Ok oid), (Err 'not-in-head) or (Err message).
(define (blob-id dir name)
  (let ([oid (git-run dir (list "rev-parse" "--verify" "-q" (string-append "HEAD:./" name)))])
    (cond
      [(Err? oid) oid]
      [(equal? (trim (Ok->value oid)) "") (Err 'not-in-head)]
      [else (Ok (trim (Ok->value oid)))])))

;; A file holding the HEAD version of `name`, whose blob id is `oid`.
;; Returns (Ok path) or (Err message).
(define (base-file dir name oid)
  (let ([path (string-append (cache-dir) "/" oid)])
    (if (path-exists? path)
        (Ok path)
        ;; `--filters` applies the same worktree conversions (autocrlf,
        ;; .gitattributes) that Helix applies to its own diff base.
        (let ([text (git-run dir (list "cat-file" "--filters" (string-append "HEAD:./" name)))])
          (if (Err? text)
              (Err "binary or non-UTF-8 file")
              (begin
                (unless (path-exists? (cache-dir))
                  (create-directory! (cache-dir)))
                ;; Write under a temporary name first, so a concurrent
                ;; request never reads a half-written file.
                (write-file! (string-append path ".tmp") (Ok->value text))
                (rename-file-or-directory! (string-append path ".tmp") path)
                (Ok path)))))))

;; `blob-id` followed by `base-file`.
(define (head-base dir name)
  (let ([oid (blob-id dir name)])
    (if (Err? oid)
        oid
        (base-file dir name (Ok->value oid)))))

;; `git diff -U0` of the file at `base-path` against `text`, as (Ok output).
;; Uses the histogram algorithm like Helix's gutter. autocrlf is turned off
;; because git would otherwise convert the file side but not stdin, and
;; every line would look changed.
(define (diff-against dir base-path text)
  (git-run dir
           (list "-c" "core.autocrlf=false" "-c" "core.safecrlf=false"
                 "diff" "--no-index" "--histogram" "-U0"
                 "--no-color" "--no-ext-diff" "--no-textconv"
                 "--" base-path "-")
           text))
