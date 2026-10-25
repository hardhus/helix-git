# helix-git

See what used to be there — right inside [Helix](https://helix-editor.com).

Helix's diff gutter already tells you *where* a line was added, changed or
deleted since the last commit. **helix-git** answers the next question: *what
was there before?* Press a key on a gutter marker and the previous version of
that hunk pops up, just like LSP hover. No side panels, no split diff views, no
external tools.

> **Status: pre-alpha.** The commands below work but have seen little use yet.

## Commands

- **`:show-diff-change`** — shows only the change under the cursor (one hunk,
  however many lines) as a colored diff in a hover-style popup. Deleted lines
  are marked with `-`, added ones with `+`. `C-d` / `C-u` scroll, `Esc` closes,
  and any other key closes the popup and then does what it normally does, so
  `]g` takes you straight to the next change. Pairs with the built-in
  `:reset-diff-change`.
- **`:open-diff-base`** — opens the file as it is in `HEAD` in a scratch buffer
  in the same window, with the same syntax highlighting and the old lines of the
  change under the cursor already selected, so you can move around and yank
  from it. Run it again (or switch to another buffer) to go back; the buffer
  closes itself when you leave it (`gp`, `ga`, the buffer picker, ...). Edits
  made there are thrown away. Helix counts the buffer as modified, so close it
  by hand with `:bc!` rather than `:bc`.

## Keybindings

helix-git binds no keys. A suggestion for your `init.scm`, next to Helix's
`space k` hover:

```scheme
(require (only-in "helix/keymaps.scm" keymap))

(keymap (global)
        (normal (space (m ":show-diff-change")
                       (M ":open-diff-base"))))
```

## Notes

- Helix reads the gutter's diff base only when a file is opened or reloaded,
  so right after a commit the gutter can still show the old markers while
  helix-git already compares with the new `HEAD`. When that happens to the file
  you are looking at, the commands say so in the status line; `:reload` brings
  the gutter up to date.
- git runs only when you use a command. A cached `HEAD` version and diff are
  reused while neither the buffer nor `HEAD` changes, so repeating a command is
  free. HEAD versions are cached under your temp directory in `helix-git/`.

## Philosophy

- Feels like Helix: one window, commands plus optional keybindings, no panels.
- Never overrides Helix's own keys or behavior.
- Cheap: git runs only when you ask, always off the UI thread, results cached.
- The diff is computed against the same base as Helix's gutter (`HEAD`,
  including unsaved buffer changes), so what you see matches the markers.

## Requirements

- Helix built with the [Steel](https://github.com/mattwparas/steel) plugin
  system (the `steel-event-system` branch of
  [mattwparas/helix](https://github.com/mattwparas/helix)) and `forge`
- `git` on your `PATH`

## Installation

Install with `forge`:

```sh
forge pkg install --git https://github.com/hardhus/helix-git.git
```

Then load it from your `init.scm`:

```scheme
(require "helix-git/helix-git.scm")
```

For development, require your local checkout instead:

```scheme
(require "/path/to/helix-git/helix-git.scm")
```

## Development

The parts that do not need the editor have tests that run with plain `steel`
from the repository root:

```sh
steel tests/hunks-test.scm
steel tests/repo-test.scm
steel tests/git-test.scm
```

## License

Licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or
  <https://www.apache.org/licenses/LICENSE-2.0>)
- MIT license ([LICENSE-MIT](LICENSE-MIT) or
  <https://opensource.org/licenses/MIT>)

at your option.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in the work by you, as defined in the Apache-2.0 license, shall be
dual licensed as above, without any additional terms or conditions.
