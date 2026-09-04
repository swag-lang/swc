#global private

/**
# Variable Declaration

Variables are declared using the 'let' or 'var' keyword, followed by a ':' and
the variable’s type.

- **'let'** — Declares an immutable variable. Once assigned, its value cannot change.
- **'var'** — Declares a mutable variable. Its value can be modified after initialization.
*/
#test
{
    let a: u32 = 1     // Immutable variable
    Swag.assert(a == 1)

    let b: string = "string"
    Swag.assert(b == "string")

    var c: s32 = 42     // Mutable variable
    c += 1
    Swag.assert(c == 43)
}

/**
# Multiple Variable Declarations

Swag allows declaring multiple variables of the same type on a single line.
*/
#test
{
    let a, b: u32 = 123
    Swag.assert(a == 123)
    Swag.assert(b == 123)
}

/**
Multiple variables of different types can also be declared on one line.
*/
#test
{
    let a: u32 = 12, b: f32 = 1.5
    Swag.assert(a == 12)
    Swag.assert(b == 1.5)
}

/**
# Default Initialization

If a variable is declared without an explicit value, it is initialized with its
type's default value. This remains true even when the following statements
overwrite every field: the compiler may remove a provably unobservable default
initialization as an optimization, without changing the program's semantics.
*/
#test
{
    var a: bool
    Swag.assert(a == false)

    var b: string?
    Swag.assert(b == null)

    var c: f64
    Swag.assert(c == 0)
}

/**
# Initialization and Optimization

There is no source-level escape hatch for uninitialized storage. Write ordinary,
safe declarations; when the compiler proves that an aggregate is fully assigned
before any read, escape, or drop, it can omit the redundant default clear itself.
*/
#test
{
    var a: bool
    a = true
    var b: string?
    b = "ready"
}

/**
# Type Inference

Swag supports **type inference**, automatically determining a variable’s type
based on its assigned value. This often eliminates the need for explicit type
annotations.
*/
#test
{
    let a = 1.5
    Swag.assert(a == 1.5)
    #assert(#typeof(a) == f32)

    let b = "string"
    Swag.assert(b == "string")
    #assert(#typeof(b) == string)

    let c = 1.5'f64
    Swag.assert(c == 1.5)
    #assert(#typeof(c) == f64)
}

/**
Type inference also applies when declaring multiple variables simultaneously.
*/
#test
{
    let a, b = true
    Swag.assert(a == true)
    Swag.assert(b == true)
    #assert(#typeof(a) == #typeof(true))
    #assert(#typeof(b) == #typeof(a))

    let c = 1.5, d = "string"
    Swag.assert(c == 1.5)
    Swag.assert(d == "string")
    #assert(#typeof(c) == f32)
    #assert(#typeof(d) == string)
}

/**
# Special Variables

Swag provides storage keywords that modify how variables are stored or accessed.
*/

/**
## Thread-Local Storage

A global variable marked with `tls` has one copy per thread. Each thread gets its own on
first access, starting from the declared value rather than from whatever another thread left
behind, and the copy is released when the thread ends.

The copy is per thread, so its address is too: taking a pointer to a thread-local global answers
the calling thread's copy, and handing that pointer to another thread points it at storage that
thread does not own.

> ATTENTION:
> A thread-local global must hold a plain value. Its per-thread copies are released without being
> dropped, so a type with an 'opDrop' leaks on every thread that touches it.
*/
tls var G = 0     // One copy per thread, each starting at 0

/**
## Global Variables

A local variable can be marked with `global` to make it global within
its function’s scope. It behaves similarly to 'static' variables in C/C++,
retaining its value between function calls.
*/

#test
{
    func toto()->s32
    {
        global var G1 = 0
        G1 += 1
        return G1
    }

    Swag.assert(toto() == 1)
    Swag.assert(toto() == 2)
    Swag.assert(toto() == 3)
}

/**
## Compile-Time Variables

Global variables marked with '#[Swag.Compiler]' exist only during compile time
and are excluded from the final runtime code.
*/
#[Swag.Compiler]
var G2 = 0

#run
{
    G2 += 5     // Executes at compile time
}
