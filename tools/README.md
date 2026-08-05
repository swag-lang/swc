# Repository tools

All project-owned Windows batch entry points live in this directory. Run them from the
repository root. Every tool takes the same shape:

```
tools\<tool> [dm] [<command>] [<name>] [options...]
```

- `dm` uses `bin/swc_devmode.exe`; without it the tools use `bin/swc.exe`.
- `<command>` is `build`, `run`, `test`, or `smoke`, when the tool has more than one.
- `<name>` is the module, suite, or script to act on; without it the tool acts on everything.
- Positionals come first and options after, so an option value is never read as a name.
- `-h` prints the tool's own usage.

Common options: `-bc <config>` selects `release`, `debug`, or `fast-debug` (default
`fast-debug`), `--all-cfg` repeats an aggregate tool in all three, `--run-arg <value>` passes
an argument to what gets launched. Anything else is forwarded to the compiler.

`_*.bat` files are internal helpers, not entry points.

## Reaching one thing

| Command | Effect |
| --- | --- |
| `tools\examples run gui2` | Launch one example |
| `tools\apps run sCrypt` | Launch one application |
| `tools\scripts snake` | Launch one standalone script |
| `tools\std dm test core` | Test one standard-library module |
| `tools\unittests dm sema` | Run one compiler suite |

## Tests and builds

| Tool | Purpose |
| --- | --- |
| `tests.bat` | The complete test set: compiler, scripts, library, examples, applications, reference |
| `unittests.bat` | The compiler suites: `cpp`, `lexer`, `parser`, `sema`, `jit`, `safety`, `sanity`, `native`, `workspace` |
| `build.bat` | Build every workspace |
| `scrypt.bat` | The privileged sCrypt/WinFsp end-to-end sandbox, kept out of `tests.bat` |

## Workspaces

| Tool | Commands | Purpose |
| --- | --- | --- |
| `std.bat` | build, test | The standard library, whole or one module |
| `examples.bat` | build, run, test, smoke | The examples, whole or one module |
| `apps.bat` | build, run, test, smoke | The applications; a build also packages their runtime files |
| `reference.bat` | build, test | The executable language reference |
| `scripts.bat` | run, smoke | The standalone example scripts; naming one runs it, naming none smokes them all |

`test` runs a module's `#test` functions and never its `#main`. `smoke` runs the real program
for a bounded number of frames, isolated from the machine, to prove it starts and keeps going.
A program without `#test` is smoked: testing it would report zero tests and prove nothing.

## Maintenance

| Tool | Purpose |
| --- | --- |
| `format.bat` | Format every Swag source workspace in place |
| `web.bat` | Regenerate the brand assets and the complete website |
| `goldens.bat` | Promote reviewed `.actual` snapshots to goldens |
| `bench.bat` | Run or regenerate the cross-language performance campaign |
| `vsix.bat` | Refresh the extension images and build the VSIX package |
| `setup.bat` | Register `bin/` in the current user's environment |

`src/Support/Memory/mimalloc/bin/bundle.bat` is intentionally not moved: it belongs to the
vendored mimalloc distribution and retains its upstream layout.
