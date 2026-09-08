#global private

/**
# Namespaces

Namespaces in Swag provide a structured way to organize symbols such as functions,
variables, and types within a specific scope. Grouping related symbols under
a namespace helps prevent naming conflicts and makes the code more modular
and maintainable.

Outside a namespace, use qualified names or bring its names into scope with
'using'. Visibility still determines whether the caller may access a symbol.
*/

// Define a simple namespace 'A'
namespace A
{
    // Function 'a' is defined within the namespace 'A'.
    func a() => 1
}

/**
# Nested Namespaces

Swag supports nested namespaces, allowing hierarchical organization of symbols.
This enables fine-grained structuring of code, which is especially helpful in
large projects. In the example below, 'C' is nested inside 'B', which is nested
inside 'A'.
*/

// Define a nested namespace 'A.B.C'
namespace A.B.C
{
    // Function 'a' is defined within the nested namespace 'A.B.C'.
    func a() => 2
}

#test
{
    // Access functions using their fully qualified namespace paths.
    Swag.assert(A.a() == 1)         // Calls 'a' from namespace 'A'
    Swag.assert(A.B.C.a() == 2)     // Calls 'a' from nested namespace 'A.B.C'
}

/**
# Qualified Namespace Access

Symbols from a namespace are accessed through their qualified name.
*/

namespace QualifiedExample
{
    const Symbol = 0     // Constant defined within namespace 'QualifiedExample'
}

const B = QualifiedExample.Symbol     // Access via fully qualified name

/**
# Visibility Blocks

A top-level 'internal { ... }' block applies module visibility to its
declarations. It does not create a namespace: the names remain in the enclosing
scope and can be used from other files in the module. Use 'private' for file-local
declarations and a named namespace when names need a qualifier.
*/

internal
{
    const OtherSymbol = 0     // Visible throughout this module.
}

const D = OtherSymbol     // No namespace qualifier is introduced by the block.

/**
# Exporting Symbols

The default declaration visibility is 'internal': other files in the same
module can use the declaration. 'public' permits access from importing modules;
'private' restricts access to the source file. '#global' can set a file-wide
default. This example file uses '#global private', and the 'internal' block
above deliberately overrides it for 'OtherSymbol'.
*/
