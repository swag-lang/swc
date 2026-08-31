# Test and improve the compiler

Compiler regressions belong at the narrowest layer that can prove them. Swag's
source tests are normal `.swg` files driven by `swc test`; the repository tools
select the appropriate stage, configuration, JIT path, or native path.

## Choose the test boundary

| Location | Use it for | Runner |
|---|---|---|
| `bin/unittests/lexer` | Tokens, trivia, escapes, and literal scanning | `swc tools\unittests.swgs dm lexer` |
| `bin/unittests/parser` | Grammar and source structure | `swc tools\unittests.swgs dm parser` |
| `bin/unittests/sema` | Types, overloads, generics, attributes, and semantic rules | `swc tools\unittests.swgs dm sema` |
| `bin/unittests/errors/<stage>` | Expected diagnostics at a compiler stage | Matching stage runner |
| `bin/unittests/jit` | Compile-time and in-memory execution | `swc tools\unittests.swgs dm jit` |
| `bin/unittests/safety` | Runtime safety guards | `swc tools\unittests.swgs dm safety` |
| `bin/unittests/sanity` | Static and lifecycle sanity analysis | `swc tools\unittests.swgs dm sanity` |
| `bin/unittests/native` | Encoding, linking, PDBs, and native execution | `swc tools\unittests.swgs dm native` |
| `src/Unittest` | C++ internals without a source-language boundary | `swc tools\unittests.swgs dm cpp` |

Do not add a source test for a command-line, linker, backend, runtime, or
internal-only behavior when its real boundary has a dedicated harness.

## Write a successful source test

Keep the file focused and deterministic. `#assert` proves compile-time facts;
`Swag.assert` proves behavior while a `#test` function executes:

```swag
#global private

#test
{
    const Expected = 42
    let value = 6 * 7

    #assert(Expected == 42)
    Swag.assert(value == Expected)
}
```

During iteration, `--test-file <substring>` keeps the whole module available but executes only
the `#test` functions declared in matching source paths. Repeat the option to select several test
files. Do not use `--file-filter` for a module test: it removes non-matching implementation files
from the compiler input.

Use `#[Swag.TestTag("golden")]` on every `#test` that records or compares a text or image golden.
`--test-tag golden` selects that category independently of filenames and assertion helpers.
Repeated tags form a union; combining `--test-file` and `--test-tag` requires both to match.

The default `test` command runs `#test` functions through both the JIT and
native backend. A layer runner narrows those paths when the layer itself is the
subject.

## Match an expected diagnostic

Put rejected programs under the matching `bin/unittests/errors` stage. Match
the stable diagnostic identifier at the source location that proves the error:

```swag
#global private

0b__0     // swc-expected-error {{lex_err_consecutive_num_sep}}
```

Use `// swc-expected-error@+ {{diagnostic_id}}` when the diagnostic belongs to
the next line. Run with `--verbose-verify` while diagnosing a match that the
harness normally consumes.

## Run the test

Build the `DevMode|x64` compiler first, then run the narrow layer:

```text
swc tools\unittests.swgs dm sema
```

Before submitting a compiler change, follow the validation sequence in the
repository's `AGENTS.md`. The common aggregate commands are:

```text
swc tools\tests.swgs dm
swc tools\tests.swgs dm --all-cfg
```

`tests.swgs` runs the default suite once. `tests.swgs --all-cfg` repeats it for
the `release` and `devmode` language configurations.

## Keep failures reviewable

- Add one regression concept per small file or clearly named group.
- Keep every individual test below 40 seconds, excluding compiler build time.
- Avoid external services, user-specific paths, timing assumptions, and random
  input without a recorded seed.
- Keep passing tests silent; use temporary `Swag.print` calls only while debugging.
- After a change that can affect shared rendering output, run
  `swc tools\goldens.swgs dm test`; it runs every golden-tagged test and reports all generated
  `.actual.txt` and `.actual.png` files without accepting them.
- Review any `*.actual.txt` snapshot before accepting it with
  `swc tools\goldens.swgs`.
- Retain a regression test after the compiler fix lands.

The executable [language reference](language.html) is also a regression suite,
but it should teach supported behavior. Put edge cases and rejected forms in
`bin/unittests` unless they materially improve the explanation.
