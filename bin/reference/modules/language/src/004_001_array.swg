#global private

/**
# Static Arrays in Swag

Static arrays are fixed-size arrays where the size is known at compile time.
Unlike dynamic arrays from the 'Std.Core' module, they cannot grow or shrink
during execution. Static arrays are ideal when size and memory usage are
deterministic.
*/

/**
# Declaring a Static Array

A static array is declared using the syntax '[N] type', where 'N' is the number
of elements.
*/
#test
{
    var array: [2] s32
    array[0] = 1
    array[1] = 2
}

/**
# Array Size and Memory

The '.count' intrinsic returns the number of elements in an array, while
'#sizeof' returns the total memory size in bytes.
*/
#test
{
    var array: [2] s32
    #assert(#typeof(array).count == 2)
    #assert(array.count == 2)
    #assert(#sizeof(array) == 2 * #sizeof(s32))
}

/**
# Obtaining the Address of an Array

The '.buffer' intrinsic retrieves the address of the first element in an array.
*/
#test
{
    var array: [2] s32
    var ptr0 = array.buffer
    ptr0[0] = 1

    var ptr1 = cast([*] s32) &array[0]
    ptr1[1] = 2

    Swag.assert(array[0] == 1)
    Swag.assert(array[1] == 2)
}

/**
# Array Literals

An array literal is a list of elements enclosed in brackets '[A, B, ...]'.
*/
#test
{
    var arr = [1, 2, 3, 4]
    #assert(arr.count == 4)
    #assert(#typeof(arr) == #type [4] s32)
}

/**
# Type Deduction in Arrays

Swag can deduce array size and element type from the initialization expression.
*/
#test
{
    var array: [?] s32 = [1, 2]
    Swag.assert(array[0] == 1)
    Swag.assert(array[1] == 2)
    #assert(array.count == 2)
    var array1 = ["10", "20", "30"]
    Swag.assert(array1[0] == "10")
    Swag.assert(array1[1] == "20")
    Swag.assert(array1[2] == "30")
    #assert(array1.count == 3)
}

/**
# Default Initialization

Static arrays are automatically initialized with zero values (0 for numbers,
'null' for strings, 'false' for booleans, etc.) unless specified otherwise.
*/
#test
{
    var array: [2] s32
    Swag.assert(array[0] == 0)
    Swag.assert(array[1] == 0)
}

/**
# Preventing Default Initialization

You can skip default initialization by using 'undefined', which improves
performance when the array will be manually initialized later.
*/
#test
{
    var array: [100] s32 = undefined
}

/**
# Constant Arrays

Arrays initialized with compile-time values can be declared as 'const', making
them immutable after declaration.
*/
#test
{
    const array = [1, 2, 3, 4]
    #assert(array[0] == 1)
    #assert(array[3] == 4)
}

/**
# Type Inference from Array Literals

If no explicit type is specified, Swag infers one element type that fits every
element, following the usual promotion rules. It is not simply the type of the
first element: a later element widens the result, and an explicit suffix on the
first one does not pin it down.

```swag
let widened = [1's32, 2.75, 3]     // a '[3] f32', not a '[3] s32'
```
*/
#test
{
    var arr = [1'f64, 2, 3, 4]
    #assert(arr.count == 4)
    #assert(#typeof(arr) == #type [4] f64)
    Swag.assert(arr[3] == 4.0)
}

/**
# Multi-Dimensional Arrays

Swag supports multi-dimensional arrays using the syntax '[X, Y, Z...]', where
each number represents a dimension.
*/
#test
{
    var array: [2, 2] s32
    array[0, 0] = 1
    array[0, 1] = 2
    array[1, 0] = 3
    array[1, 1] = 4
}

/**
# C/C++ Style Nested Arrays

Nested array syntax is also accepted, similar to C/C++, and '[i, j]' indexing
works on it just as well.

> WARNING:
> The two spellings are **not** the same type. '[2, 2] s32' is one array with two
> dimensions, while '[2][2] s32' is a one-dimensional array of '[2] s32'. They do
> not convert to each other, so pick one spelling per API and keep it.
*/
#test
{
    var array: [2, 2] s32
    array[0, 0] = 1
    array[0, 1] = 2
    array[1, 0] = 3
    array[1, 1] = 4

    // A different type from 'array', even though it indexes the same way.
    var array1: [2][2] s32
    array1[0, 0] = 1
    array1[0, 1] = 2
    array1[1, 0] = 3
    array1[1, 1] = 4
}

/**
# Array Size Deduction

Swag can infer the dimensions of arrays — including multi-dimensional ones —
directly from the initialization expression.
*/
#test
{
    var array  = [1, 2, 3, 4]
    var array1 = [[1, 2], [3, 4]]
    #assert(array.count == 4)
    #assert(array1.count == 2)
}

/**
# Single Value Initialization

An entire array can be initialized with a single value. This feature applies to
variables (not constants) and works for basic types such as integers, floats,
strings, booleans, and runes.
*/
#test
{
    var arr: [2, 2] bool = true
    Swag.assert(arr[0, 0] == true)
    Swag.assert(arr[1, 1] == true)
    var arr1: [5, 10] string = "string"
    Swag.assert(arr1[0, 0] == "string")
    Swag.assert(arr1[4, 9] == "string")
}
