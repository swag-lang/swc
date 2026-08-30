#global private
/**
This reference teaches Swag through small, executable examples. The compiler
builds every '.swg' file in this module and runs each '#test' block, so the code
beside the explanations is also the documentation's regression suite.

# What This Reference Covers

The chapters progress from source organization and built-in types to control
flow, user-defined types, functions, generics, reflection, safety, compile-time
execution, metaprogramming, and foreign interoperability.

The reference focuses on the **language and compiler runtime**. Containers,
filesystem access, text formatting, threading, and other library facilities
live under 'bin/std/modules' and are outside this module's scope.

# Running the Examples

From a repository checkout, test only this module with:

```text
swc test --workspace <repository-root>/bin/reference --workspace-module language
```

The shorter forms are equivalent:

```text
swc test -w <repository-root>/bin/reference -m language
```

Run the command without '-m language' to test every module in the reference
workspace. The 'test' command uses the 'devmode' build configuration by
default; select another registered configuration with '--build-cfg' (or '-bc'):

```text
swc test -w <repository-root>/bin/reference -m language -bc release
```

# How to Read the Examples

- A '#test' block runs only for the 'test' command.
- '#assert' checks a condition while compiling.
- 'Swag.assert' checks a condition while the generated program runs.
- Deliberately invalid examples stay commented out and explain the diagnostic
  they are intended to produce.
- Most declarations are private to this module so examples do not accidentally
  become part of another module's API.

> TIP:
> Copy a '#test' body into a function or executable while experimenting. Keep
> '#assert' for compile-time facts and 'Swag.assert' for runtime behavior.

# Accuracy and Scope

Examples in this module deliberately avoid standard-library dependencies unless
a chapter is specifically about integration. Passing tests prove that the shown
syntax and runtime results agree with the compiler version that shipped them.
Prose still explains constraints that cannot be expressed by a successful test,
such as rejected syntax or platform-specific linking requirements.
*/
