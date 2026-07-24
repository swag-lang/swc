#global private

/**
# The Smallest Executable

'#main' is the entry point of an executable module. '@print' is a compiler
intrinsic available without importing a standard module.

```swag
#main
{
    @print("Hello, world!\n")
}
```

Only one '#main' may exist in an executable. This reference uses '#test' blocks
instead because the test runner owns the module entry point.
*/

const ShowHelloOutput = false

#test
{
    if ShowHelloOutput do
        @print("Hello, world!\n")
}

/**
# Compute Part of the Message at Compile Time

A function does not need a special compile-time implementation. '#run' asks the
compiler to execute an ordinary function and embed its result.
*/
func helloAudience()->string
{
    return "Swag"
}

const HelloAudience = #run helloAudience()
#assert(HelloAudience == "Swag")

#test
{
    if ShowHelloOutput do
        @print("Hello, ", HelloAudience, "!\n")
}

/**
# Reusable Compile-Time Functions

'#[Swag.ConstExpr]' allows calls with constant arguments to participate in
constant expressions without writing '#run' at every call site.
*/
#[Swag.ConstExpr]
func punctuation(excited: bool)->string
{
    return excited ? "!" : "."
}

const HelloSuffix = punctuation(true)
#assert(HelloSuffix == "!")

/**
# Generate a Declaration

'#ast' returns source text that is parsed in place. This technique is reserved
for cases where generics, mixins, or macros cannot express the required shape.
*/
#ast
{
    return "const GeneratedHello = \"Hello from generated code\""
}

#assert(GeneratedHello == "Hello from generated code")

/**
The progression is deliberate: start with normal runtime code, move pure work to
compile time when it is useful, and generate source only when the program's
structure itself must vary.
*/
