/**
# Swag Language Overview

Swag is a modern and flexible programming language designed for ease of use,
combining a strong type system with an intuitive syntax. This section introduces
the fundamental concepts of Swag through concise examples, covering variables,
functions, control flow, and more.
*/

/**
# Constants and Variables

Use 'const' to define constants, 'var' for mutable variables, and 'let' for
immutable variables (single-assignment, set once at runtime).

- 'const' values are immutable and must be initialized at declaration.
- 'var' values can be reassigned.
- 'let' values are immutable after initialization.
*/
#test
{
    const Pi   = 3.14159     // Constant value, cannot be changed
    var radius = 10          // Mutable variable
    let height = 100         // Immutable variable (single assignment)
}

/**
# Mutability and Reassignment

Variables declared with 'var' can be reassigned as needed.
*/
#test
{
    var counter = 0
    counter = 5 // Reassigning the value of 'counter'
}

/**
Constants ('const') and immutable variables ('let') cannot be reassigned.
*/
#test
{
    const MaxCount = 10
    // MaxCount = 12  // Error: Cannot assign to constant

    let width = 50
    // width = 60     // Error: Cannot reassign an immutable variable
}

/**
# Type Inference

Swag infers types automatically if they can be deduced from assigned values.
*/
#test
{
    let greeting = "Hello, Swag!"     // Inferred as 'string'
    var age      = 25                 // Inferred as 's32'
}

/**
You can also explicitly declare a type when desired.
*/
#test
{
    let name:  string = "Alice"
    var score: s32 = 100
}

/**
# Constants and Immutability

'let' and 'const' emphasize immutability. 'let' allows runtime initialization,
while 'const' is typically resolved at compile-time.

# Printing Values

Use the '@print' intrinsic to display output in the console.
*/
// @TODO: Re-enable this variadic print helper when user-defined variadic calls are stable again.
// const CanPrint = false // Must be 'true' to show '@print' results
//
// func print(x: ...)
// {
//     if CanPrint do
//         @print(x)
// }
//
// #test
// {
//     let name = "Swag"
//     print("Welcome to ", name, " language!\n")
// }

/**
This prints: 'Welcome to Swag language!'
*/

/**
# Comments

Swag supports both single-line and multi-line comments.
*/
#test
{
    // This is a single-line comment

    /*
    This is a multi-line comment
    that spans multiple lines.
    */
}

/**
# Semicolons

Semicolons are optional at the end of statements.
They’re only needed when placing multiple statements on the same line.
*/
// @TODO: Re-enable this example when the local variadic 'print' helper no longer trips codegen.
// #test
// {
//     let a = 5
//     let b = 10
//     print(a + b, "\n") // Outputs 15
// }

/**
# Integers and Floating-Point Numbers

Swag supports both integer and floating-point numeric types.
*/
// @TODO: Re-enable this example when the local variadic 'print' helper no longer trips codegen.
// #test
// {
//     let maxHeight: u32 = 500        // Unsigned 32-bit integer
//     let distance:  f64 = 42.195     // Double-precision float
//
//     let result = maxHeight + 50
//     print("New height: ", result, "\n")
// }

/**
# Strings

Strings are UTF-8 encoded and handle international text naturally.
*/
#test
{
    let message = "Hello, 世界!"
    // @TODO: Re-enable this line when the local variadic 'print' helper no longer trips codegen.
    // print(message, "\n")
}

/**
# Tuples

Tuples group multiple values of possibly different types.
They are useful for returning multiple values or bundling related data.
*/
// @TODO: Re-enable this tuple unpacking example when struct literal decomposition is accepted here.
// #test
// {
//     let person = {name: "Alice", age: 30, isActive: true}
//     let (name, age, isActive) = person
//
//     print(name, " is ", age, " years old. Active: ", isActive, "\n")
//
//     // Access tuple elements by index:
//     print(person.item0, " is ", person.item1, " years old.\n")
// }

/**
# Control Flow

Swag uses 'if', 'for', and 'switch' for flow control.
Curly braces '{}' are optional; you may use 'do' blocks instead.
*/
// @TODO: Re-enable this example when the local variadic 'print' helper no longer trips codegen.
// #test
// {
//     let temperature = 30
//     if temperature > 25 do
//         print("It's hot!\n")
//     else do
//         print("It's cool!\n")
// }

/**
You can also use braces for control blocks.
*/
// @TODO: Re-enable this example when the local variadic 'print' helper no longer trips codegen.
// #test
// {
//     let temperature = 30
//     if temperature > 25
//     {
//         print("It's hot!\n")
//     }
//     else
//     {
//         print("It's cool!\n")
//     }
// }

/**
Swag supports both 'for' and 'while' loops.
*/
// @TODO: Re-enable this example when the local variadic 'print' helper no longer trips codegen.
// #test
// {
//     // Iterate 10 times
//     for 10
//     {
//         print("Iteration: ", @index, "\n")
//     }
//
//     for var i: u32 = 0; i < 10; i += 2
//     {
//         print("Iteration: ", i, "\n")
//     }
//
//     var countdown: u32 = 5
//     while countdown > 0
//     {
//         print("T-minus ", countdown, "\n")
//         countdown -= 1
//     }
// }

/**
# 'foreach' Loop

'foreach' iterates over collections such as arrays.
*/
// @TODO: Re-enable this foreach literal example when array literal iteration is stable in this context.
// #test
// {
//     var numbers = [1, 2, 3, 4, 5]
//     foreach num in numbers
//     {
//         print("Number: ", num, "\n")
//     }
// }

/**
# Functions

Functions encapsulate reusable blocks of logic.
*/
// @TODO: Re-enable this example when the local variadic 'print' helper no longer trips codegen.
// #test
// {
//     func add(a: s32, b: s32)->s32
//     {
//         return a + b
//     }
//
//     let result = add(10, 5)
//     print("Result: ", result, "\n") // Outputs 15
// }

/**
Functions can also return multiple values via tuples.
*/
// @TODO: Re-enable when tuple-style destructuring of multi-value string returns works in all build configs again.
// #test
// {
//     func splitName()->{ x: string, y: string }
//     {
//         return {"a", "b"}
//     }
//
//     let (firstName, lastName) = splitName()
//     @assert(firstName == "a")
//     @assert(lastName == "b")
// }

/**
# Error Handling

Swag uses 'throw', 'try', and 'catch' for robust error management.
Errors are treated as values, not exceptions.

# Propagating Errors with 'throw' and 'try'
*/
func divide(a: s32, b: s32)->s32 throw
{
    if b == 0
    {
        throw Swag.BaseError{"Division by zero!"}
    }
    return a / b
}

// @TODO: Re-enable this example when the local variadic 'print' helper no longer trips codegen.
// #test
// {
//     let result = try divide(10, 2)
//     print("Result: ", result, "\n") // Outputs 5
// }

/**
# Handling Errors with 'catch'

Use 'catch' to handle errors locally. The intrinsic '@err' holds the error value.
*/
// @TODO: Re-enable this example when the local variadic 'print' helper no longer trips codegen.
// #test
// {
//     let result = catch divide(10, 0)
//     if @err != null
//     {
//         print("Error: ", @err, "\n")
//     }
//     else
//     {
//         print("Result: ", result, "\n")
//     }
// }

/**
# Dismissing Errors with 'trycatch'

'trycatch' dismisses errors and continues execution,
assigning a default value to the target variable.
*/
// @TODO: Re-enable this example when the 'trycatch' helper path no longer trips semantic analysis.
// func safeDivide(a: s32, b: s32)->s32
// {
//     return trycatch divide(a, b)
// }
//
// @TODO: Re-enable this example when the local variadic 'print' helper no longer trips codegen.
// #test
// {
//     let result = safeDivide(10, 0)
//     print("Result: ", result, "\n") // Outputs 0 (default value)
// }
