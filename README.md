# helix-git

See what used to be there — right inside [Helix](https://helix-editor.com).

Helix's diff gutter already tells you *where* a line was added, changed or
deleted since the last commit. **helix-git** answers the next question: *what
was there before?* Press a key on a gutter marker and the previous version of
that hunk pops up, just like LSP hover. No side panels, no split diff views, no
external tools.

> **Status: pre-alpha.** Nothing usable yet; the MVP is being built.

## Planned for v0.1.0

- **`:show-diff-change`** — shows only the change under the cursor (one hunk,
  however many lines) as a colored diff in a hover-style popup. Deleted lines
  are marked with `-`. Any key closes it. Works naturally with the built-in
  `]g` / `[g` and `:reset-diff-change`.
- **`:open-diff-base`** — opens the file as it is in `HEAD` in a read-only
  scratch buffer in the same window, with the same syntax highlighting and the
  old lines of the current change already selected, so you can move around and
  yank from it. `ga` takes you back.

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
