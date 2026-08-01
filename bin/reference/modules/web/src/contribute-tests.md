# Test and improve the compiler

Compiler regressions belong at the narrowest layer that can prove them. Swag's
source tests are normal `.swg` files driven by `swc test`; the repository tools
select the appropriate stage, configuration, JIT path, or native path.

## Choose the test boundary

| Location | Use it for | Runner |
|---|---|---|
| `bin/unittests/lexer` | Tokens, trivia, escapes, and literal scanning | `tools\test-lexer-suite.bat dm` |
| `bin/unittests/parser` | Grammar and source structure | `tools\test-parser-suite.bat dm` |
| `bin/unittests/sema` | Types, overloads, generics, attributes, and semantic rules | `tools\test-semantic-suite.bat dm` |
| `bin/unittests/errors/<stage>` | Expected diagnostics at a compiler stage | Matching stage runner |
| `bin/unittests/jit` | Compile-time and in-memory execution | `tools\test-jit-suite.bat dm` |
| `bin/unittests/safety` | Runtime safety guards | `tools\test-safety-suite.bat dm` |
| `bin/unittests/sanity` | Static and lifecycle sanity analysis | `tools\test-sanity-suite.bat dm` |
| `bin/unittests/native` | Encoding, linking, PDBs, and native execution | `tools\test-native-suite.bat dm` |
| `src/Unittest` | C++ internals without a source-language boundary | `tools\test-cpp-units.bat dm` |

Do not add a source test for a command-line, linker, backend, runtime, or
internal-only behavior when its real boundary has a dedicated harness.

## Write a successful source test

Keep the file focused and deterministic. `#assert` proves compile-time facts;
`@assert` proves behavior while a `#test` function executes:

```swag
#global private

#test
{
    const Expected = 42
    let value = 6 * 7

    #assert(Expected == 42)
    @assert(value == Expected)
}
```

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
tools\test-semantic-suite.bat dm
```

Before submitting a compiler change, follow the validation sequence in the
repository's `AGENTS.md`. The common aggregate commands are:

```text
tools\test-all-workspaces.bat dm
tools\test-all-configurations.bat dm
```

`test-all-workspaces.bat` runs the default suite once. `test-all-configurations.bat` repeats it for
`release`, `debug`, and `fast-debug` language configurations.

## Keep failures reviewable

- Add one regression concept per small file or clearly named group.
- Keep every individual test below 40 seconds, excluding compiler build time.
- Avoid external services, user-specific paths, timing assumptions, and random
  input without a recorded seed.
- Keep passing tests silent; use temporary `@print` calls only while debugging.
- Review any `*.actual.txt` snapshot before accepting it with
  `tools\accept-test-goldens.bat`.
- Retain a regression test after the compiler fix lands.

The executable [language reference](language.html) is also a regression suite,
but it should teach supported behavior. Put edge cases and rejected forms in
`bin/unittests` unless they materially improve the explanation.
