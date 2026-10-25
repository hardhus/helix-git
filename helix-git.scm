;; helix-git: see the previous version of changed code inside Helix.
;; SPDX-License-Identifier: MIT OR Apache-2.0
;;
;; Commands:
;;   :show-diff-change  the change under the cursor, as it was in HEAD, in a popup
;;   :open-diff-base    the file as it is in HEAD, in a scratch buffer (toggle)
;;
;; git only runs when one of these commands is used, always on a background
;; thread. The diff base is the same as the one of Helix's diff gutter: the
;; file in HEAD against the buffer, unsaved changes included.

(require "helix/editor.scm")
(require "helix/misc.scm")
(require "helix/ext.scm")
(require (prefix-in helix.static. "helix/static.scm"))
(require (prefix-in helix. "helix/commands.scm"))
(require-builtin helix/core/text as text.)

(require "src/git.scm")
(require "src/hunks.scm")
(require "src/repo.scm")
(require "src/popup.scm")

(provide helix-git-version
         show-diff-change
         open-diff-base)

(define (helix-git-version)
  "0.0.3")

;;; Caches. Only ever touched on the editor thread.

;; file path -> (list head-commit blob-id). A file's blob id depends only on
;; the commit, which is read from .git without starting git.
(define blob-ids (hash))
;; file path -> (list blob-id text-hash (list blob-id base-path hunks))
(define diffs (hash))
;; (list file-path old-commit blob-id) -> 'stale or 'fresh: whether the file
;; in `old-commit` differs from its HEAD version `blob-id`.
(define stale-checks (hash))

(define (cached-blob-id path head)
  (let ([entry (hash-try-get blob-ids path)])
    (and entry head (equal? (first entry) head) (second entry))))

(define (cached-diff path oid text-hash)
  (let ([entry (hash-try-get diffs path)])
    (and entry (equal? (first entry) oid) (equal? (second entry) text-hash) (third entry))))

;;; Which HEAD the gutter shows.
;;
;; Helix reads the gutter's diff base only when a file is opened or reloaded,
;; so after a commit the gutter can still show changes against the old HEAD
;; while these commands already use the new one. Remember the commit HEAD
;; pointed to at those moments (a few small file reads, no git process) to
;; tell the user when a `:reload` is needed.

;; file path -> commit id, or #false when unknown. Keyed by path like the
;; other caches, since the gutter's diff base belongs to the file.
(define gutter-heads (hash))

(define (path-head-commit path)
  (let* ([parts (split-path path)]
         [git-dir (and parts (find-git-dir (first parts)))])
    (and git-dir (head-commit git-dir))))

(define (remember-gutter-head! doc-id)
  (let ([path (and (editor-doc-exists? doc-id) (editor-document->path doc-id))])
    (when path
      (set! gutter-heads (hash-insert gutter-heads path (path-head-commit path))))))

(register-hook 'document-opened remember-gutter-head!)

(register-hook 'post-command
               (lambda (name)
                 (cond
                   [(equal? name "reload") (remember-gutter-head! (editor->doc-id (editor-focus)))]
                   [(equal? name "reload-all") (for-each remember-gutter-head! (editor-all-documents))])))

(define stale-note "the gutter still shows the old HEAD, :reload to update it")

;;; Snapshot of the focused document, taken on the editor thread.

(struct request (doc-id path dir name text line last-line head gutter-head))

(define (current-request)
  (let* ([doc-id (editor->doc-id (editor-focus))]
         [path (editor-document->path doc-id)]
         [parts (and path (split-path path))])
    (and parts
         (let* ([rope (editor->text doc-id)]
                [text (text.rope->string rope)]
                [lines (text.rope-len-lines rope)]
                ;; A trailing newline leaves an empty last rope line.
                [last-line (max 0 (- lines (if (ends-with? text "\n") 2 1)))]
                [git-dir (find-git-dir (first parts))]
                [head (and git-dir (head-commit git-dir))])
           ;; Files opened before this plugin was loaded were never seen by
           ;; the hook; assume their gutter is current.
           (unless (hash-contains? gutter-heads path)
             (set! gutter-heads (hash-insert gutter-heads path head)))
           (request doc-id
                    path
                    (first parts)
                    (second parts)
                    text
                    (text.rope-char->line rope (cursor-position))
                    last-line
                    head
                    (hash-ref gutter-heads path))))))

(define (error-message err)
  (cond
    [(equal? err 'not-in-head) "Not in HEAD (new or untracked file)"]
    [(string? err) err]
    [else (to-string err)]))

;; Run `on-done` on the editor thread with (Ok (list oid base-path hunks)) or
;; (Err reason) for the focused document, and whether the gutter is out of
;; date for it. Starts at most two git processes, usually one, and none when
;; the buffer and HEAD are unchanged since the last call. Right after a
;; commit, one more checks whether the commit changed this file at all.
(define (with-hunks req on-done)
  (let* ([path (request-path req)]
         [head (request-head req)]
         [known-oid (cached-blob-id path head)]
         [text-hash (hash-code (request-text req))]
         [known-diff (and known-oid (cached-diff path known-oid text-hash))]
         [old-head (request-gutter-head req)]
         [head-moved? (and old-head head (not (equal? old-head head)))]
         [known-stale (and head-moved? known-oid (hash-try-get stale-checks (list path old-head known-oid)))])
    (if (and known-diff (or (not head-moved?) known-stale))
        (on-done (Ok known-diff) (equal? known-stale 'stale))
        (spawn-native-thread
         (lambda ()
           (let* ([dir (request-dir req)]
                  [name (request-name req)]
                  ;; Ask for the commit that was read, not "HEAD", so the
                  ;; cache entry matches its key even if HEAD moves meanwhile.
                  [oid (if known-oid (Ok known-oid) (blob-id dir name (or head "HEAD")))]
                  [base (if (Ok? oid) (base-file dir name (Ok->value oid)) oid)]
                  [diff (if (Ok? base) (diff-against dir (Ok->value base) (request-text req)) base)]
                  [hunks (and (Ok? diff) (parse-hunks (Ok->value diff)))]
                  [result (cond
                            [(not (Ok? diff)) diff]
                            [(and (empty? hunks) (string-contains? (Ok->value diff) "Binary files"))
                             (Err "Binary file")]
                            [else (Ok (list (Ok->value oid) (Ok->value base) hunks))])]
                  [stale (cond
                           [(not (and head-moved? (Ok? result))) #false]
                           [known-stale known-stale]
                           [else
                            (let ([before (blob-id dir name old-head)])
                              (if (and (Ok? before) (equal? (Ok->value before) (Ok->value oid)))
                                  'fresh
                                  'stale))])])
             (hx.with-context
              (lambda ()
                (when (Ok? result)
                  (let ([oid (first (Ok->value result))])
                    (when head
                      (set! blob-ids (hash-insert blob-ids path (list head oid))))
                    (set! diffs (hash-insert diffs path (list oid text-hash (Ok->value result))))
                    (when stale
                      (set! stale-checks (hash-insert stale-checks (list path old-head oid) stale)))))
                (on-done result (equal? stale 'stale))))))))))

(define (still-focused? req)
  (equal? (editor->doc-id (editor-focus)) (request-doc-id req)))

(define (report message stale?)
  (if stale?
      (set-warning! (string-append message "; " stale-note))
      (set-status! message)))

(define (warn-if-stale stale?)
  (when stale?
    (set-warning! (string-append "HEAD moved: " stale-note))))

;;@doc
;; Show the change under the cursor as it was in HEAD, in a popup.
;; Esc closes it, C-d / C-u scroll, any other key closes it and goes through.
(define (show-diff-change)
  (let ([req (current-request)])
    (if (not req)
        (set-status! "No file to compare with HEAD")
        (with-hunks req
                    (lambda (result stale?)
                      (when (still-focused? req)
                        (if (Err? result)
                            (set-status! (error-message (Err->value result)))
                            (let* ([hunks (third (Ok->value result))]
                                   [h (hunk-at hunks (request-line req) (request-last-line req))])
                              (cond
                                [(empty? hunks) (report "No changes since HEAD" stale?)]
                                [(not h) (report "No change under the cursor" stale?)]
                                [else
                                 (show-hunk-popup (hunk-lines h))
                                 (warn-if-stale stale?)])))))))))

;;; The HEAD version buffer.

;; The scratch buffer showing a HEAD version, and the document it came from.
(define base-doc #false)
(define source-doc #false)

(define (base-doc-open?)
  (and base-doc (editor-doc-exists? base-doc)))

(define (select-lines! doc-id start count)
  (let* ([rope (editor->text doc-id)]
         [lines (text.rope-len-lines rope)]
         [start (min start (max 0 (- lines 1)))]
         [from (text.rope-line->char rope start)]
         [to (text.rope-line->char rope (min lines (+ start count)))])
    (helix.static.set-current-selection-object! (helix.static.range->selection (helix.static.range from to)))
    (helix.static.align_view_center)))

(define (show-base! req base-path hunks)
  (let ([base-text (with-handler (lambda (_) #false) (read-file base-path))]
        [language (editor-document->language (request-doc-id req))]
        [range (base-range-for hunks (request-line req) (request-last-line req))])
    (if (not base-text)
        (set-error! "Could not read the HEAD version, try again")
        (begin
          (if (base-doc-open?)
              (editor-switch-action! base-doc (Action/Replace))
              (helix.new))
          ;; Replace everything, including the empty line a new buffer starts with.
          (helix.static.select_all)
          (helix.static.replace-selection-with base-text)
          (set! base-doc (editor->doc-id (editor-focus)))
          (set! source-doc (request-doc-id req))
          (set-scratch-buffer-name! (string-append "[HEAD] " (request-name req)))
          (when language
            (helix.set-language language))
          (select-lines! base-doc (first range) (second range))))))

;; Close the HEAD version buffer and land on `return-to`.
(define (close-base! return-to)
  (when (base-doc-open?)
    (let ([doc base-doc])
      (set! base-doc #false)
      (editor-switch-action! doc (Action/Replace))
      (helix.buffer-close!)))
  (when (and return-to (editor-doc-exists? return-to))
    (editor-switch-action! return-to (Action/Replace))))

;; The HEAD version buffer is a view, not a document to keep: it goes away as
;; soon as you leave it, so it never shows up as "unsaved" on quit.
;; The event's doc id is not used: when switching buffers in the same view
;; (`gp`, `ga`, the buffer picker) Helix reports the newly focused document
;; instead of the one that lost focus, so look at what has focus now.
(register-hook 'document-focus-lost
               (lambda (_)
                 (when (base-doc-open?)
                   (let ([now-focused (editor->doc-id (editor-focus))])
                     (unless (equal? now-focused base-doc)
                       (close-base! now-focused))))))

;;@doc
;; Open the file as it is in HEAD in a scratch buffer, with the old lines of
;; the change under the cursor selected. Run it again to go back.
(define (open-diff-base)
  (if (and (base-doc-open?) (equal? (editor->doc-id (editor-focus)) base-doc))
      (close-base! source-doc)
      (let ([req (current-request)])
        (if (not req)
            (set-status! "No file to compare with HEAD")
            (with-hunks req
                        (lambda (result stale?)
                          (when (still-focused? req)
                            (if (Err? result)
                                (set-status! (error-message (Err->value result)))
                                (let ([value (Ok->value result)])
                                  (show-base! req (second value) (third value))
                                  (warn-if-stale stale?))))))))))
