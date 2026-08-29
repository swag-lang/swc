#global private
/**
# The 'swc' Command Line

The language is named Swag; the compiler executable is 'swc'. Ask the installed
binary for the authoritative option set:

```text
swc help
swc help test
```

The current commands are:

| Command | Purpose |
|---|---|
| 'new' | Create a runnable script or an executable workspace module |
| 'clean' | Remove what a build produced, and the caches kept between runs |
| 'build' | Compile and emit native artifacts without running them |
| 'run' | Build, then run emitted executables |
| 'test' | Run source-driven tests and '#test' functions |
| 'format' | Rewrite source using canonical formatting |
| 'syntax' | Parse source without semantic analysis or code generation |
| 'sema' | Parse and type-check source without backend code generation |
| 'doc' | Parse and type-check source, then generate configured documentation |
| 'unittest' | Run the compiler's internal C++ unit tests |

# Creating a Starter

Create and run the smallest script:

```text
swc new script hello
swc hello.swgs
```

The path defaults to 'hello.swgs'. When a path has no extension, 'new script'
adds '.swgs'. Existing paths are never overwritten.

Create an executable module in a new workspace:

```text
swc new module hello
swc run --workspace hello --workspace-module hello
```

By default, the workspace and module share the requested name. Use
'--workspace' to add a module to an existing workspace, or to create a
workspace with a different name:

```text
swc new module tools --workspace hello
swc new module app --workspace my-project
```

# Selecting Input

Use one input model per invocation:

| Option | Meaning |
|---|---|
| '--workspace PATH', '-w PATH' | Use a workspace containing 'modules/<name>' |
| '--workspace-module NAME', '-m NAME' | Select one module inside that workspace |
| '--module PATH', '-mf PATH' | Compile a module directly |
| '--module-file PATH' | Run one module setup file, then compile its module |
| '--directory PATH', '-d PATH' | Add a directory of source files |
| '--file PATH', '-f PATH' | Add an individual source file |

'--workspace' is available to 'new', 'clean', 'build', 'run', 'test', 'sema',
and 'doc'. '--workspace-module' is available to the five compilation commands
and to 'clean'. The
'format', 'syntax', and compiler-internal 'unittest' commands use the direct
module, module-file, directory, or file modes instead.

Where workspace mode is accepted, it excludes the direct module, directory,
and file input modes. '--workspace-module' is meaningful only with
'--workspace'. For 'new module', '--workspace' names the workspace to create
or extend.

# Build Configurations

'--build-cfg' (or '-bc') accepts:

| Value | Intended use |
|---|---|
| 'devmode' | Default: full safety/sanity with optimized code and lighter allocation tracking |
| 'release' | Optimized code, static sanity on, runtime safety and tracking off |

Each configuration also asks for a backend optimization level, which
'--optim-level' ('-O') overrides: '0' runs no backend optimization, '1' runs
everything that costs no compilation time, and '2' also runs what does.
'devmode' asks for '1' and 'release' for '2'.

Neither configuration emits debug information by default. Add '--debug' to a
'test', 'build', 'run', or 'smoke' command when a debugger needs symbols, types,
and source line mappings. The option does not change optimization or guard policy.

The target architecture currently exposed by '--arch' is 'x86_64'. Select the
artifact with '--artifact-kind' ('-ak'): 'executable', 'shared-library',
'static-library', or 'export'.

# Common Workflows

```text
swc new script hello
swc new module app --workspace my-project
swc build -w <workspace> -m app -bc release
swc run   -w <workspace> -m app --run-arg first --run-arg second
swc sema  -w <workspace> -m app
swc doc   -w <workspace> -m app --doc-output-dir <directory>
swc syntax -mf <workspace>/modules/app
swc format -mf <workspace>/modules/app --dry-run
```

'--dry-run' previews planned stages without executing compile-time code, native
tools, tests, or emitted programs. '--show-config' prints the resolved command,
environment, toolchain, and artifact configuration, then exits.

# Cleaning

'swc clean' removes what a build wrote, and nothing else. It compiles nothing,
so it still answers on a tree that no longer builds.

| Option | Removes |
|---|---|
| '--workspace PATH' | The '.output', '.tmp', and '.dep' directories of that workspace |
| '--workspace-module NAME' | That module's artifacts alone, keeping the '.dep' directory the workspace shares |
| '--module PATH' | The '.output' directory under that module root, and '--out-dir' and '--work-dir' when they are set |
| '--cache' | Every dependency copy a script filled outside a workspace |
| '--cache-days N' | With '--cache', only the copies unused for at least N days |

```text
swc clean -w <workspace>
swc clean -w <workspace> -m app
swc clean --cache
swc clean --cache --cache-days 7
swc clean -w <workspace> --dry-run
```

The command needs at least one of those targets, and never chooses one on its
own. A directory that is not there counts as already clean, and '--dry-run'
reports what each target holds while removing nothing.

A script reads its dependencies from a copy rather than from where they were
built, because the compiler loads their shared libraries into its own process:
'swc tools/std.swgs' rebuilds the very library it is running on, and could not
replace a file the run has locked. Each copy is named after what it holds, so
every script importing the same build shares one, a rebuilt dependency lands
beside the copy a running script is reading instead of replacing it, and no run
can observe a copy while it is being filled.

Nothing invalidates a copy, because nothing can make one wrong: a dependency
built again is different bytes, and different bytes are a different copy. What
the old ones cost is disk. Publishing a copy removes the ones no run has used
for a week, and '--cache' gives back the rest on demand.

# Formatting

'swc format' rewrites sources in the canonical Swag style, which is built into
the compiler. A Swag tree needs no configuration file to be formatted the way
every other Swag tree is.

| Option | Effect |
|---|---|
| '--style swag' | Use the canonical Swag style; this is the default |
| '--style preserve' | Normalize nothing: every option keeps the source as written |
| '--dump-config' | Print the resolved configuration as a complete '.swc-format' file, then exit |

A '.swc-format' file layers over that style. The formatter looks for one in the
file's own directory and in every parent, and the closest one wins, so a subtree
can depart from the style of the tree it sits in. A 'style' key inside such a
file rebases the whole option set before the rest of the file applies,
wherever in the file it sits:

```text
style = preserve
indent-style = spaces
```

That is also how a subtree is kept out of the formatter's way: a vendored or
generated directory holding a '.swc-format' with 'style = preserve' alone is
rendered back byte for byte, so nothing in it is ever rewritten.

'--dump-config' writes the answer for the first named input, or for the current
directory when there is none. Every option carries its value and its accepted
values, so redirecting the output into a '.swc-format' file gives a complete,
documented starting point:

```text
swc format --dump-config -d src > src/.swc-format
```

The canonical style deliberately leaves two dimensions alone. Line endings
belong to the checkout rather than to the style, so they are preserved. And the
style has no column budget: the formatter never adds and never removes a
statement break, so where a line wraps is the author's decision and it survives
formatting, which is what keeps a hand-laid data table intact. Setting
'column-limit' turns wrapping on, and the formatter then breaks greedily, one
break at a time, as high in the expression as it can.

# Documentation Generation

`swc doc` uses the module's 'BuildCfg.genDoc' configuration. The documentation
kind can generate a public API page, a numbered examples document, or one page
per source file.

| Option | Effect |
|---|---|
| `--doc-output-dir PATH` | Write generated pages under 'PATH' |
| `--css PATH` | Override the generated stylesheet path |
| `--output-doc` / `--no-output-doc` | Enable or suppress documentation files |

In an API module, prefix a source comment line with `//!` to include it in the
module-wide **File documentation** section. Mark every line that belongs to the
block; the marker is removed before Markdown rendering. A later `//!` block in
the same file starts a new paragraph. Marked lines are emitted only in that
section, even when adjacent to a declaration. Ordinary `//` comments remain
local to their declarations and licence comments are not published implicitly.

The command also generates the public runtime API page once per output
directory.

# Test Controls

By default, 'swc test' runs '#test' functions through both the JIT and native
backend and emits native output. Narrow that behavior when diagnosing a layer:

| Option | Effect |
|---|---|
| '--test-jit', '-tj' / '--no-test-jit' | Enable or disable JIT tests |
| '--test-native', '-tn' / '--no-test-native' | Enable or disable native tests |
| '--test-file' 'TEXT' | Run '#test' functions from source paths containing 'TEXT'; repeat to select a union |
| '--output' / '--no-output' | Enable or disable native artifact generation |
| '--lex-only' | Stop after lexing source-driven tests |
| '--syntax-only' | Stop after parsing |
| '--sema-only' | Stop after semantic analysis |
| '--verbose-verify', '-vv' | Show diagnostics normally consumed by expected-error tests |

The three '*-only' modes are mutually exclusive. For this reference, keep the
default JIT and native paths enabled so examples verify both execution engines.
*/
