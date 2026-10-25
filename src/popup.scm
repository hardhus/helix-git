;; A hover-style popup for a diff hunk, placed and styled like Helix's own
;; popups (helix-term/src/ui/popup.rs): below the cursor when there is room,
;; above it otherwise, on the `ui.popup` background.
;; SPDX-License-Identifier: MIT OR Apache-2.0

(require "helix/components.scm")
(require "helix/editor.scm")
(require "helix/misc.scm")

(provide show-hunk-popup)

(define popup-name "helix-git-diff-change")

;; Same limits as Helix's Popup.
(define min-height 6)
(define max-height 26)
(define max-width 120)

;; `content` is the rendered markdown for the lines from `offset` on.
;; `visible` is how many lines fit, as of the last render.
(struct popup-state (lines offset row col content visible) #:mutable)

(define (any? pred lst)
  (cond
    [(empty? lst) #false]
    [(pred (car lst)) #true]
    [else (any? pred (cdr lst))]))

;; A fenced ```diff block, so the theme's diff.plus / diff.minus colors apply.
(define (lines->markdown lines)
  (let ([fence (if (any? (lambda (line) (string-contains? line "```")) lines) "````" "```")])
    (string-append fence "diff\n" (string-join lines "\n") "\n" fence)))

(define (refresh-content! state)
  (set-popup-state-content! state
                            (markdown-component (lines->markdown (list-tail (popup-state-lines state)
                                                                            (popup-state-offset state))))))

(define (render-popup state rect buf)
  (let* ([view-width (area-width rect)]
         [view-height (area-height rect)]
         [row (popup-state-row state)]
         [below? (> view-height (+ row min-height))]
         [max-h (min max-height (if below? (- view-height 1 row) row))]
         [max-w (min max-width (max 0 (- view-width 2)))]
         [size (native-component-required-size (popup-state-content state) (list max-w max-h))]
         [width (min max-w (if size (first size) max-w))]
         [height (min max-h (if size (second size) max-h))]
         [x (if (<= view-width (+ (popup-state-col state) width 2))
                (max 0 (- view-width width 2))
                (popup-state-col state))]
         [y (if below? (+ row 1) (max 0 (- row height)))]
         [area (area x y width height)])
    ;; The markdown component keeps a 1-cell margin on every side.
    (set-popup-state-visible! state (max 1 (- height 2)))
    (buffer/clear-with buf area (theme-scope "ui.popup"))
    (render-native-component (popup-state-content state) area buf)))

(define (ctrl? event)
  (equal? (key-event-modifier event) key-modifier-ctrl))

(define (scroll! state lines)
  (let* ([total (length (popup-state-lines state))]
         [last-offset (max 0 (- total (popup-state-visible state)))]
         [offset (max 0 (min last-offset (+ (popup-state-offset state) lines)))])
    (set-popup-state-offset! state offset)
    (refresh-content! state)
    event-result/consume))

;; Like Helix's hover: Esc / C-c close, C-d / C-u scroll, and any other key
;; closes the popup and then does what it normally does.
(define (handle-popup-event state event)
  (let ([half (max 1 (quotient (popup-state-visible state) 2))])
    (cond
      [(not (key-event? event))
       (if (mouse-event? event) event-result/ignore-and-close event-result/ignore)]
      [(key-event-escape? event) event-result/close]
      [(and (ctrl? event) (equal? (key-event-char event) #\c)) event-result/close]
      [(or (key-event-page-down? event) (and (ctrl? event) (equal? (key-event-char event) #\d)))
       (scroll! state half)]
      [(or (key-event-page-up? event) (and (ctrl? event) (equal? (key-event-char event) #\u)))
       (scroll! state (- half))]
      [else event-result/ignore-and-close])))

;; Show `lines` (each starting with "-" or "+") next to the primary cursor.
(define (show-hunk-popup lines)
  (let* ([cursor (current-cursor)]
         [pos (and (list? cursor) (first cursor))]
         [state (popup-state lines 0 (if pos (position-row pos) 0) (if pos (position-col pos) 0) #false max-height)])
    (refresh-content! state)
    (pop-last-component-by-name! popup-name)
    (push-component! (new-component! popup-name
                                     state
                                     render-popup
                                     (hash "handle_event" handle-popup-event)))))
