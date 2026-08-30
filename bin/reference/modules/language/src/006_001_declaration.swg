#global private

/**
# Basic Struct Declaration

This section illustrates a basic 'struct' declaration in Swag.
Notice that the 'var' keyword is not required when declaring fields within the struct.
Each field is defined with a specific type.
*/
#test
{
    struct MyStruct
    {
        name: #null string     // Field 'name' of type 'string'
    }

    struct MyStruct1
    {
        x:    s32          // Field 'x' of type 's32'
        y, z: s32          // Fields 'y' and 'z' of type 's32', declared together
        val:  bool         // Field 'val' of type 'bool'
        myS:  MyStruct     // Field 'myS' of type 'MyStruct', demonstrating a nested struct
    }
}

/**
# Field Separators

Fields within a struct can be separated by either a comma ',' or a semicolon ';'.
The trailing separator is optional and can be omitted.
*/
#test
{
    // Fields separated by commas
    struct MyStruct
    {
        name: #null string
        val1: bool
    }

    struct MyStruct1
    {
        x:    s32
        y, z: s32
        val:  bool
        myS:  MyStruct
    }
}

/**
# Anonymous Structs

Structs can be declared anonymously when used as variable types.
This is particularly useful for lightweight, temporary groupings of data.
*/
#test
{
    var tuple: struct
    {
        x: f32     // Field 'x' of type 'f32'
        y: f32     // Field 'y' of type 'f32'
    }

    var tuple1: struct
    {
        x, y: f32     // Anonymous struct with fields 'x' and 'y' of type 'f32'
    }

    tuple.x = 1.0
    tuple.y = 2.0
    Swag.assert(tuple.x == 1.0)
    Swag.assert(tuple.y == 2.0)
}

#test
{
    struct MyStruct
    {
        rgb: struct
        {
            x, y, z: f32     // Nested anonymous struct for RGB values
        }

        hsl: struct
        {
            h, s, l: f32     // Nested anonymous struct for HSL values
        }
    }
}

/**
# Default Field Values

Fields within a struct can be initialized with default values,
providing a convenient way to ensure fields are set to a known state.
*/
#test
{
    struct MyStruct
    {
        x: s32    = 666       // Field 'x' initialized with default value 666
        y: string = "454"     // Field 'y' initialized with default value '454'
    }

    let v = MyStruct{}     // Initializing struct with default values
    Swag.assert(v.x == 666)
    Swag.assert(v.y == "454")
}

/**
# Struct Initialization

Struct variables can be initialized in multiple ways, providing flexibility
in how you set up your structs. Every form initializes with '=': naming the type
in the initializer ('MyStruct{...}') or in the annotation ('let v: MyStruct = {...}')
is a matter of where the type reads best, never of syntax.
*/
#test
{
    struct MyStruct
    {
        x, y: s32 = 1     // Both 'x' and 'y' initialized to 1
    }

    // Default initialization
    let v0: MyStruct
    Swag.assert(v0.x == 1)
    Swag.assert(v0.y == 1)

    // Positional initialization
    let v1 = MyStruct{10, 20}
    Swag.assert(v1.x == 10)
    Swag.assert(v1.y == 20)

    // Named initialization
    let v2 = MyStruct{y: 20}
    Swag.assert(v2.x == 1)
    Swag.assert(v2.y == 20)

    // Tuple initialization
    let v3: MyStruct = {10, 20}
    Swag.assert(v3.x == 10)
    Swag.assert(v3.y == 20)
}

/**
# Const Structs

A struct can be defined as a constant, provided its values can be evaluated
at compile time. This ensures immutability throughout program execution.
*/
#test
{
    struct MyStruct
    {
        x: s32    = 666
        y: string = "454"
    }

    const X = MyStruct{50, "value"}

    #assert(X.x == 50)     // Compile-time assertion
    #assert(X.y == "value")
}

/**
# Structs as Function Arguments

Functions take a struct argument as an immutable **value**. Under the hood the
compiler passes the struct's address rather than copying it, but the callee
cannot write through the parameter, so the code behaves as if a private copy had
been made — at zero copy cost. To let a function modify the caller's struct,
pass its address explicitly through a pointer parameter ('*Struct3').
*/

struct Struct3
{
    x, y, z: s32 = 666
}

func toto(v: Struct3)
{
    Swag.assert(v.x == 5)
    Swag.assert(v.y == 5)
    Swag.assert(v.z == 666)
}

func titi(v: Struct3)
{
    Swag.assert(v.x == 5)
    Swag.assert(v.y == 666)
}

#test
{
    // Calling with explicit values
    toto(Struct3{5, 5, 666})

    // Type inferred from arguments
    toto({5, 5, 666})

    // Partial initialization
    titi({5})
    titi({5, 666})

    // Named field initialization
    titi({x: 5, z: 5})
}
