# Format Command Roadmap

This file is the roadmap for `swc format`, measured against clang-format, rustfmt, gofmt,
prettier, black and `zig fmt`. The compiler that hosts it is
[todo.compiler.md](todo.compiler.md).

It is not the repository's discovery backlog. Defects and leads belong in the `findings.*` files,
which hold evidence; this file holds intent. [README.md](README.md) has the whole layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

## Where the command already stands

8 488 lines, 130 options covering whitespace, indentation, wrapping, braces, switch layout,
alignment (including two-column declaration grids and outlier exclusion), spacing, attributes,
comments, `using` blocks and numeric literals; a cascading `.swc-format` resolved from the file's
directory upward with parent inheritance
([FormatOptionsLoader.cpp](../src/Format/FormatOptionsLoader.cpp)); `swc-format off`/`on` regions;
nine passes over a token-and-AST model; and 5 225 lines of C++ tests over 205 cases, the
best-tested subsystem in the compiler. On option count it is already in clang-format's league.

---

### T-016 — It cannot be used in CI, and cannot be used by an editor

Three missing modes, all small, all blocking real use.

- **No check mode.** `--dry-run` suppresses the write and the stats block counts what *would* be
  rewritten, but there is no `--check`, no `--list-different`, no diff output, and no exit-code
  contract for "this file was not formatted". clang-format has `--dry-run -Werror`, rustfmt
  `--check`, gofmt `-l` and `-d`, prettier `--check`. Without it, formatting cannot be enforced on
  a branch — which is exactly what a canonical style needs. It also leaves an author unable to
  answer "which file did that run touch, and why": a rewrite whose only effect is the configured
  end-of-line style is invisible to `git diff` and to an IDE diff, so a run that reports N
  rewritten files can look like it changed nothing at all. `--list-different` naming the files is
  the smallest fix for both.
- **No stdin/stdout.** The command reads paths and writes files back in place. Every editor
  integration wants to format a buffer that may not be on disk, and to receive the result rather
  than have the file rewritten under it.
- **No range formatting.** clang-format has `--lines` and `--offset/--length`; rustfmt and
  prettier have equivalents. Format-selection is the interaction people actually use.

### T-017 — There is no canonical Swag style

- Every option defaults to `Preserve`. Out of the box the formatter normalizes almost nothing;
  the repository's own style lives in `bin/.swc-format`.
- gofmt, black and `zig fmt` owe their adoption to the opposite choice: one style, no options, no
  argument. Swag currently offers the configurability of clang-format without the default that
  makes a formatter a community norm.
- Fix: publish the repository's own profile as the built-in default (a named `--style` with the
  current `Preserve`-everything behavior kept as an explicit opt-out). This is a policy decision
  first and a small code change second, and it should be made before the option count grows again.

### T-018 — Wrapping is greedy, and files that do not parse are skipped

- There is no penalty model or layout solver anywhere in `src/Format` — `Pass.Wrap.cpp` decides
  per construct, locally. clang-format solves a penalty function over the whole unwrapped line and
  prettier searches a Wadler-style document for the best fit. On dense nested expressions that
  difference is visible.
- The cost of that shows up as options. Every shape a solver would have found had to be named and
  implemented by hand: `hug-trailing-block-argument` for the call whose last argument is a data
  table or a closure, `align-outlier-gap` for the run that one long line would otherwise stretch
  across the screen. Both are right, both are local, and neither generalizes — the next such shape
  will need a twelfth option. That is the argument for the solver, and it should be weighed before
  the option count grows again.
- Separately, a file that fails to parse is counted and skipped
  ([FormatJob.cpp:40](../src/Format/FormatJob.cpp#L40)). clang-format formats broken files because it
  works on tokens — which is what makes format-on-type possible.
- Neither is necessarily worth matching. Both should be a stated position rather than an
  unexamined limit: decide whether the formatter's contract is "valid files, locally good layout"
  and write that down, or invest in the solver.
