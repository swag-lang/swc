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

Compiler-provided intrinsic values and operations live in the built-in 'Swag'
namespace. Collection views expose '.count' and '.buffer' through ordinary member
access instead. Availability depends on the intrinsic and context:
'Swag.compiler()' is compile-time only, while math and memory intrinsics can also
generate runtime code.

Examples of intrinsic functions:

```swag
Swag.min()
Swag.max()
Swag.sqrt()
Swag.print()
```

*/
