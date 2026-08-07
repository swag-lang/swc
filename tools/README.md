# Repository tools

All project-owned entry points of this repository live in this directory. Each one is a Swag
script: run it by name, or double-click it. Every tool takes the same shape:

```
tools\<tool>.swgs [dm] [<command>] [<name>] [options...]
```

- `dm` uses `bin/swc_devmode.exe`; without it the tools drive `bin/swc.exe`.
- `<command>` is `build`, `run`, `test`, or `smoke`, when the tool has more than one.
- `<name>` is the module, suite, or script to act on; without it the tool acts on everything.
- Positionals come first and options after, so an option value is never read as a name.
- `-h` prints the tool's own usage.

Common options: `-bc <config>` selects `release`, `debug`, or `fast-debug` (default
`fast-debug`), `--all-cfg` repeats an aggregate tool in all three, `--run-arg <value>` passes
an argument to what gets launched. Anything else is forwarded to the compiler.

## How a tool is built

A tool is an ordinary Swag script. It states the sources it is made of, and calls into the
shared implementation under [src/](src), one file per family. There is no launcher, no wrapper,
and no environment protocol: the compiler hands a script everything after its own path, and a
script finds the repository from its own location.

The compiler a tool *drives* is `bin/swc.exe`, started as a child process and never the one that
ran the tool. That is what lets a tool say that a freshly built compiler is broken.

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
| `tests.swgs` | The complete test set: compiler, scripts, library, examples, applications, reference |
| `unittests.swgs` | The compiler suites: `cpp`, `lexer`, `parser`, `sema`, `jit`, `safety`, `sanity`, `native`, `workspace` |
| `build.swgs` | Build every workspace |
| `scrypt.swgs` | The privileged sCrypt/WinFsp end-to-end sandbox, kept out of `tests.swgs` |

## Workspaces

| Tool | Commands | Purpose |
| --- | --- | --- |
| `std.swgs` | build, test | The standard library, whole or one module |
| `examples.swgs` | build, run, test, smoke | The examples, whole or one module |
| `apps.swgs` | build, run, test, smoke | The applications; a build also packages their runtime files |
| `reference.swgs` | build, test | The executable language reference |
| `scripts.swgs` | run, smoke | The standalone example scripts; naming one runs it, naming none smokes them all |

`test` runs a module's `#test` functions and never its `#main`. `smoke` runs the real program
for a bounded number of frames, isolated from the machine, to prove it starts and keeps going.
A program without `#test` is smoked: testing it would report zero tests and prove nothing.

## Maintenance

| Tool | Purpose |
| --- | --- |
| `format.swgs` | Format every Swag source workspace in place |
| `web.swgs` | Regenerate the brand assets and the complete website |
| `goldens.swgs` | Promote reviewed `.actual` snapshots to goldens |
| `bench.swgs` | Run or regenerate the cross-language performance campaign |
| `vsix.swgs` | Refresh the extension images and build the VSIX package |
| `setup.swgs` | Register `bin/` in the current user's environment |

The one batch file left in the repository is `src/Support/Memory/mimalloc/bin/bundle.bat`: it
belongs to the vendored mimalloc distribution and retains its upstream layout.
