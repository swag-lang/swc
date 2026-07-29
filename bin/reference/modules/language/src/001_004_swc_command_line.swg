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
| 'build' | Compile and emit native artifacts without running them |
| 'run' | Build, then run emitted executables |
| 'test' | Run source-driven tests and '#test' functions |
| 'format' | Rewrite source using canonical formatting |
| 'syntax' | Parse source without semantic analysis or code generation |
| 'sema' | Parse and type-check source without backend code generation |
| 'doc' | Parse and type-check source, then generate configured documentation |
| 'unittest' | Run the compiler's internal C++ unit tests |

There is no 'new' project generator in the current CLI.

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

'--workspace' and '--workspace-module' are available to 'build', 'run', 'test',
'sema', and 'doc'. The 'format', 'syntax', and compiler-internal 'unittest'
commands use the direct module, module-file, directory, or file modes instead.

Where workspace mode is accepted, it excludes the direct module, directory,
and file input modes. '--workspace-module' is meaningful only with
'--workspace'.

# Build Configurations

'--build-cfg' (or '-bc') accepts:

| Value | Intended use |
|---|---|
| 'debug' | Full safety/sanity, allocation diagnostics, no optimization |
| 'fast-debug' | Default: full safety/sanity with optimized code and lighter allocation tracking |
| 'release' | Optimized code, static sanity on, runtime safety and tracking off |

The target architecture currently exposed by '--arch' is 'x86_64'. Select the
artifact with '--artifact-kind' ('-ak'): 'executable', 'shared-library',
'static-library', or 'export'.

# Common Workflows

```text
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

# Documentation Generation

`swc doc` uses the module's 'BuildCfg.genDoc' configuration. The documentation
kind can generate a public API page, a numbered examples document, or one page
per source file.

| Option | Effect |
|---|---|
| `--doc-output-dir PATH` | Write generated pages under 'PATH' |
| `--css PATH` | Override the configured stylesheet link |
| `--ext EXTENSION` | Override the configured output extension |
| `--output-doc` / `--no-output-doc` | Enable or suppress documentation files |

The command also generates the public runtime API page once per output
directory.

# Test Controls

By default, 'swc test' runs '#test' functions through both the JIT and native
backend and emits native output. Narrow that behavior when diagnosing a layer:

| Option | Effect |
|---|---|
| '--test-jit', '-tj' / '--no-test-jit' | Enable or disable JIT tests |
| '--test-native', '-tn' / '--no-test-native' | Enable or disable native tests |
| '--output' / '--no-output' | Enable or disable native artifact generation |
| '--lex-only' | Stop after lexing source-driven tests |
| '--syntax-only' | Stop after parsing |
| '--sema-only' | Stop after semantic analysis |
| '--verbose-verify', '-vv' | Show diagnostics normally consumed by expected-error tests |

The three '*-only' modes are mutually exclusive. For this reference, keep the
default JIT and native paths enabled so examples verify both execution engines.
*/
