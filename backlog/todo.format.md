# Format Command Roadmap

This file is the roadmap for `swc format`, measured against clang-format, rustfmt, gofmt,
prettier, black and `zig fmt`. The compiler that hosts it is
[todo.compiler.md](todo.compiler.md).

It is not the repository's discovery backlog. Defects and leads belong in the `findings.*` files,
which hold evidence; this file holds intent. [README.md](README.md) has the whole layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

## Where the command already stands

8 442 lines, 130 options covering whitespace, indentation, wrapping, braces, switch layout,
alignment (including two-column declaration grids and outlier exclusion), spacing, attributes,
comments, `using` blocks and numeric literals; a cascading `.swc-format` resolved from the file's
directory upward with parent inheritance
([FormatOptionsLoader.cpp](../src/Format/FormatOptionsLoader.cpp)); `swc-format off`/`on` regions;
nine passes over a token-and-AST model; and 5 257 lines of C++ tests over 206 cases, the
best-tested subsystem in the compiler. On option count it is already in clang-format's league.

---

### T-016 — Add a CI check mode

`--dry-run` suppresses writes and counts what *would* be rewritten, but there is no check-mode
exit-code contract, no list of differing files, and no optional diff. Add those as one CI-facing
contract. The file list must also expose end-of-line-only rewrites that `git diff` can hide.

- Related: T-017

### T-115 — Format stdin to stdout

The command only reads paths and writes files in place. Accept a buffer on standard input and
return the formatted result on standard output so an editor can format unsaved content without a
filesystem round trip.

- Related: T-116, T-124

### T-116 — Format a selected source range

Add a line- or offset-based range contract for editor format-selection. Define how the requested
range expands to syntactic boundaries and which returned edits may fall outside it.

- Related: T-115, T-117

### T-017 — There is no canonical Swag style

- Every option defaults to `Preserve`. Out of the box the formatter normalizes almost nothing;
  the repository's own style lives in `bin/.swc-format`.
- gofmt, black and `zig fmt` owe their adoption to the opposite choice: one style, no options, no
  argument. Swag currently offers the configurability of clang-format without the default that
  makes a formatter a community norm.
- Fix: publish the repository's own profile as the built-in default (a named `--style` with the
  current `Preserve`-everything behavior kept as an explicit opt-out). This is a policy decision
  first and a small code change second, and it should be made before the option count grows again.

### T-018 — Replace or explicitly retain greedy wrapping

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
- Decide whether the formatter's contract deliberately remains "locally good layout" or gains a
  penalty/document solver. Record and test that decision before adding more shape-specific
  wrapping options.

### T-117 — Format source that is temporarily invalid

A file that fails to parse is counted and skipped
([FormatJob.cpp:40](../src/Format/FormatJob.cpp#L40)). Define and implement the token-level recovery
contract needed for format-on-type, without making successful parsing a prerequisite.

- Related: T-115, T-116, T-018
