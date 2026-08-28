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
#assert(!#defined(DOES_NOT_EXISTS))     // Ensure the symbol is not defined.
#assert(#defined(Global))               // Confirms 'Global' is defined.
var Global = 0                          // Define a global variable 'Global'.

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
# The '#command' and '#cfg' Values

'#command' reports one of three source-compilation modes:

- 'Swag.CompilerCommand.Test' for 'swc test';
- 'Swag.CompilerCommand.Format' for 'swc format';
- 'Swag.CompilerCommand.Build' for 'build', 'run', 'syntax', 'sema', and the
  compiler-internal 'unittest' path.

'#cfg' is the selected build-configuration name, such as '"fast-debug"' or
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
  #global if false            // Skip file content.
  #global if #command == Swag.CompilerCommand.Format // Include this file only when formatting.
  #global if #command == Swag.CompilerCommand.Test   // Include this file only when running tests.
  #global public                      // All symbols become public.
  #global private                    // All symbols are private to the module.
  #global namespace Toto              // Place all symbols in namespace 'Toto'.
  #global if DEBUG == true     // Conditional compilation for the file.
  #global #[Swag.Safety(.All, true)]  // Apply an attribute to all declarations.
  #global export                      // Export the full file as-is into the module API output.
*/

/**
# The '#foreignlib' Directive
Register an external import library with the native linker. Pass the logical
library name without a platform extension; the linker selects the appropriate
file for the active toolchain.

Example:
  #foreignlib("kernel32")

This directive only supplies the native link dependency. Declare imported
symbols separately with '#[Swag.Foreign]'.
*/
