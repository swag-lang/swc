#global private

/**
# Naming

User-defined identifiers, such as variables, constants, and function names,
must begin with either an underscore ('_') or an ASCII letter. Identifiers may
then include underscores, ASCII letters, and digits.

Examples:
*/

const thisIsAValidIdentifier0   = 0
const this_is_also_valid        = 0
const this_1_is_2_also__3_valid = 0

/**
However, identifiers cannot start with two underscores, as this prefix is reserved
by the compiler.
*/

// const __this_is_invalid = 0

/**
# Compiler Instructions

Names beginning with '#' belong to compiler syntax: built-in directives, static
queries, qualifiers, modifiers, and user-defined selectors at specific
extension points such as custom iteration.

Examples of compiler instructions:
```swag
#assert
#run
#main
```

*/

/**

# Intrinsics

Names beginning with '@' represent compiler-provided intrinsic values and
operations. Availability depends on the intrinsic and context: '@compiler' is
compile-time only, while math and memory intrinsics can also generate runtime
code.

Examples of intrinsic functions:

```swag
@min()
@max()
@sqrt()
@print()
```

*/
