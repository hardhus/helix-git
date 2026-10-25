;; Parsing `git diff -U0` output into hunks, and looking hunks up by line.
;; SPDX-License-Identifier: MIT OR Apache-2.0
;;
;; This module is pure: no editor or process access, so it can be tested
;; with plain `steel`.

(provide parse-hunks
         hunk-at
         base-range-for
         hunk?
         hunk-old-start
         hunk-old-count
         hunk-new-start
         hunk-new-count
         hunk-lines)

;; Line numbers are 0-based and ranges are [start, start + count), the same
;; convention Helix uses for its own diff hunks (helix-vcs/src/diff.rs).
;; `lines` is the hunk body, each line keeping its "-" or "+" prefix.
(struct hunk (old-start old-count new-start new-count lines))

;; "12,3" -> (12 3), "12" -> (12 1)
(define (parse-range-numbers text)
  (if (string-contains? text ",")
      (map string->number (split-once text ","))
      (list (string->number text) 1)))

;; git numbers a non-empty range from its first line (1-based). An empty
;; range is numbered by the line *before* it, which is exactly the 0-based
;; index of the line after it.
(define (zero-based start count)
  (if (= count 0) start (- start 1)))

;; "@@ -12,3 +12,0 @@ ..." -> (old-start old-count new-start new-count)
(define (parse-header line)
  (let* ([parts (split-whitespace line)]
         [old (parse-range-numbers (substring (list-ref parts 1) 1 (string-length (list-ref parts 1))))]
         [new (parse-range-numbers (substring (list-ref parts 2) 1 (string-length (list-ref parts 2))))])
    (list (zero-based (first old) (second old))
          (second old)
          (zero-based (first new) (second new))
          (second new))))

(define (strip-cr line)
  (trim-end-matches line "\r"))

(define (make-hunk header body)
  (hunk (list-ref header 0) (list-ref header 1) (list-ref header 2) (list-ref header 3) (reverse body)))

;; Parse the full output of `git diff -U0` into a list of hunks, in order.
(define (parse-hunks diff-text)
  (let loop ([lines (split-many diff-text "\n")]
             [header #f]
             [body '()]
             [acc '()])
    (cond
      [(empty? lines)
       (reverse (if header (cons (make-hunk header body) acc) acc))]
      [(starts-with? (car lines) "@@ ")
       (let ([next-acc (if header (cons (make-hunk header body) acc) acc)]
             [next-header (parse-header (car lines))])
         (loop (cdr lines) next-header '() next-acc))]
      ;; Everything before the first "@@" is the file header ("---", "+++", ...).
      [(and header (or (starts-with? (car lines) "-") (starts-with? (car lines) "+")))
       (loop (cdr lines) header (cons (strip-cr (car lines)) body) acc)]
      ;; "\ No newline at end of file" and anything else.
      [else (loop (cdr lines) header body acc)])))

;; The hunk under `line`, or #false. A pure removal has no lines of its own;
;; like Helix's gutter it belongs to the line right after the removed block,
;; or to the last line when the block was removed from the end of the file.
(define (hunk-at hunks line last-line)
  (let loop ([hunks hunks])
    (cond
      [(empty? hunks) #false]
      [(let* ([h (car hunks)]
              [start (hunk-new-start h)]
              [count (hunk-new-count h)])
         (if (= count 0)
             (or (= line start) (and (> start last-line) (= line last-line)))
             (and (>= line start) (< line (+ start count)))))
       (car hunks)]
      [else (loop (cdr hunks))])))

;; Where `line` of the buffer lives in the base version, as (start count).
;; Inside a hunk this is the hunk's old lines; elsewhere it is the matching
;; unchanged line, shifted by the hunks above it.
(define (base-range-for hunks line last-line)
  (let ([h (hunk-at hunks line last-line)])
    (if h
        (list (hunk-old-start h) (hunk-old-count h))
        (let loop ([hunks hunks] [offset 0])
          (if (or (empty? hunks) (> (hunk-new-start (car hunks)) line))
              (list (+ line offset) 0)
              (let ([h (car hunks)])
                (loop (cdr hunks) (+ offset (- (hunk-old-count h) (hunk-new-count h))))))))))
