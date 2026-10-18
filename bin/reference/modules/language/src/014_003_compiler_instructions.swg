#global if true
#global private

/**
# The '#assert' Directive
The '#assert' directive performs a static assertion during compilation.
If the condition is false, compilation fails with an error message.
Use it to enforce compile-time invariants and validate assumptions.
*/
#assert(true)     // Always passes; no error.

/**
# The '#defined' Query
'#defined(SYMBOL)' checks at compile time whether a symbol exists in the
current context. It returns true if defined, false otherwise. Useful for
conditional compilation before referencing variables, constants, or functions.
*/
#assert(not #defined(DOES_NOT_EXISTS))     // Ensure the symbol is not defined.
#assert(#defined(Global))     // Confirms 'Global' is defined.
var Global = 0     // Define a global variable 'Global'.

/**
# Static Control with '#static'
'#static' applies compile-time semantics to the control statement that follows.
The condition or selected value is evaluated at compile time, and only the
selected branch is retained. The ordinary 'elif' and 'else' keywords complete a
static 'if'; they do not repeat the '#static' prefix.
*/

const DEBUG   = 1
const RELEASE = 0

#static if DEBUG
{
    // Compiled because DEBUG == 1.
}
elif RELEASE
{
    // Would compile if RELEASE were true and DEBUG were false.
}
else
{
    // Compiled if neither DEBUG nor RELEASE is true.
}

/**
'#static switch' selects one section from a compile-time value. Multiple values
can share a section, and 'default' is optional. Unlike a runtime 'switch', this
construct does not create runtime control flow and does not use 'break' or
'fallthrough'.
*/

enum StaticBuildMode
{
    Debug
    Release
}

const StaticMode = StaticBuildMode.Release

#static switch StaticMode
{
case .Debug:   #error("debug mode is not selected")
case .Release: const StaticSelection = 42
default:       #error("unknown build mode")
}

#assert(StaticSelection == 42)

/**
Add '#complete' to require the sections to cover every declared value of an
enum. As for a runtime 'switch', a missing value is an error and a 'default' is
then rejected, because there is nothing left for it to catch.
*/

const StaticExhaustive = StaticBuildMode.Debug

#static switch #complete StaticExhaustive
{
case .Debug:   const StaticExhaustiveSelection   = 1
case .Release: const StaticExhaustiveSelection = 2
}

#assert(StaticExhaustiveSelection == 1)

/**
# Compiler Tags Before Module Setup

Compiler tags are fixed inputs to a compilation. They are available while compiling the runtime,
before any '#run' in 'module.swg' executes. '#hastag("Name")' reports whether a tag is present;
`#gettag("Name", Type, fallback)` reads its value, or returns the fallback when it is absent.
An ordinary tag can hold 'false' and still be present. The allocator capability tags below use
presence to mean that support is compiled: setting one to 'false' removes it instead.

| Predefined tag | Type | Default presence | Meaning |
| --- | --- | --- | --- |
| 'Swag.Endian' | 'string' | Every configuration | Target byte order; '"little"' on x86-64 |
| 'swag.test' | 'bool' | The 'test' command | Compile-time test marker |
| 'Swag.AllocatorSafety' | 'bool' | 'devmode' | Compile allocator address checks, double-free checks, freed-block canaries and keyed free-list links |
| 'Swag.AllocatorDiagnostics' | 'bool' | 'devmode' | Compile allocator tracking, stack capture, leak reports, memory filling, quarantine and electric mode |

Both allocator tags are absent by default in 'release', including `release --debug`: debug
information is independent of allocator instrumentation. Add or remove either capability on
the command line. A name without a value means 'true'; 'false' removes the tag. Only Boolean
values are accepted, and the last occurrence of each allocator tag wins.

```text
swc build --module mymodule --build-cfg release --tag Swag.AllocatorDiagnostics
swc build --module mymodule --build-cfg release --tag Swag.AllocatorSafety --tag Swag.AllocatorDiagnostics
swc build --module mymodule --build-cfg devmode --tag Swag.AllocatorDiagnostics=false
swc build --module mymodule --build-cfg devmode --tag Swag.AllocatorSafety=false --tag Swag.AllocatorDiagnostics=false
```

These are capabilities, not requests to activate every diagnostic mode. With diagnostics
compiled, the module can choose its modes through 'Swag.Build.Config.allocatorLeaks',
'allocatorCaptureStack', 'allocatorTrackAllocations', 'allocatorElectricMode' and
'allocatorFillMemory'. These fields exist only when 'Swag.AllocatorDiagnostics' is present;
accessing one without that tag is a compilation error. Directly configuring a diagnostic mode on 'Swag.Allocator' without its
capability panics. Removing diagnostics also disables the preset's default leak reporting.

Tags select compiled support; they do not change configuration precedence. An explicit
'--build-cfg' preset still reapplies its allocator settings after module setup. A diagnostic
allocator can also select its modes directly through 'Swag.Allocator.configure'.

Allocator checks, including compiler-inserted guards and value-borrow invalidation, depend on
'Swag.AllocatorSafety', independently of later changes to 'Swag.Build.Config.safetyGuards'.
General language guards elsewhere still follow '#safety' and
'safetyGuards'; the allocator tags do not change that contract. Diagnostic modes retain the
checks they need even when 'Swag.AllocatorSafety' is absent.

Module setup cannot add or remove these tags. The runtime executing the setup and the runtime
compiled for the final program receive the same capability selection. The command-line
configuration and tag overrides participate in cache validation; rebuild a dependency when
its capability selection changes, and use a consistent selection across linked modules.
Public allocator diagnostic fields retain their layout but do not activate excluded code.

```swag
#static if #hastag("Swag.AllocatorDiagnostics")
{
    // Declarations that need the diagnostic allocator.
}

const TargetEndian = #gettag("Swag.Endian", string, "unknown")
#assert(TargetEndian == "little")
```

# The '#command' and '#cfg' Values

'#command' reports one of three source-compilation modes:

- 'Swag.CompilerCommand.Test' for 'swc test';
- 'Swag.CompilerCommand.Format' for 'swc format';
- 'Swag.CompilerCommand.Build' for 'build', 'run', 'smoke', 'syntax', 'sema', 'doc', and the
  compiler-internal 'unittest' path.

'#cfg' is the selected build-configuration name, such as '"devmode"' or
'"release"'. Use these values for genuine source differences, not as a
replacement for safety and optimization attributes.

```swag
#static if #command == Swag.CompilerCommand.Test
{
    // Test-only declarations.
}

#static if #cfg == "release"
{
    // Release-specific declarations.
}
```
*/

/**
# The '#error' and '#warning' Directives
'#error' raises a compile-time error with a custom message.
'#warning' emits a compile-time warning without stopping compilation.
Useful for enforcing checks and surfacing build-time information.
*/
#static if false
{
    #error("this is an error")        // Compile-time error (if reached).
    #warning("this is a warning")     // Compile-time warning (if reached).
}

/**
# The '#global' Directive
Place '#global' at the top of a source file to apply global settings or
attributes across the entire file. Controls compilation and symbol visibility.

Examples (write these as top-level directives):

```swag
#global if false                                 // Skip this file.
#global if #command == Swag.CompilerCommand.Format // Include only when formatting.
#global if #command == Swag.CompilerCommand.Test   // Include only when testing.
#global public                                   // Set public declaration visibility.
#global private                                  // Set file-local declaration visibility.
#global namespace Example                        // Put declarations in 'Example'.
#global if DEBUG == true                          // Select the file from a constant.
#global #[Swag.Safety(.All, true)]                 // Apply the attribute file-wide.
#global export                                   // Export the file into the module API.
```

These are alternatives, not one file's preamble. A named aggregate's members
start at 'internal' independently of the enclosing visibility; group public
fields explicitly inside it.
*/

/**
# The '#foreignlib' Directive
Register an external import library with the native linker. Pass the logical
library name without a platform extension; the linker selects the appropriate
file for the active toolchain.

Example:

```swag
#foreignlib("kernel32")
```

This directive only supplies the native link dependency. Declare imported
symbols separately with '#[Swag.Foreign]'.
*/
