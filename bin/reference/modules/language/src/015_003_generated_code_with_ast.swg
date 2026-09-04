#global private

/**
# The '#ast' Block

The '#ast' block lets you dynamically generate and inject Swag code at compile time.
It produces a string that the compiler treats as if it were written directly in the
source. This allows for dynamic, context-dependent code generation.
*/

/**
# Basic '#ast' Usage
A '#ast' block can return a simple string expression representing Swag code.
*/
#test
{
    #ast "var x = 666"
    Swag.assert(x == 666)
}

/**
# Returning Source from '#ast'
A '#ast' block can include logic and must return a string to compile.
*/
#test
{
    var cpt = 2
    #ast
    {
        const INC = 5
        return "cpt += " ++ INC
    }

    Swag.assert(cpt == 7)
}

/**
# Generating Structs and Enums
You can use '#ast' inside struct or enum definitions to generate members dynamically.
*/
#test
{
    struct MyStruct
    {
        #ast
        {
            return "x, y: s32 = 666"
        }
    }

    let v: MyStruct
    Swag.assert(v.x == 666)
    Swag.assert(v.y == 666)
}

/**
# Generating Generic Code
'#ast' works with generics for flexible and reusable code generation.
*/
#test
{
    struct(T) MyStruct
    {
        #ast
        {
            return "x, y: " ++ #typeof(T).name
        }

        z: string?
    }

    let v: MyStruct'bool
    #assert(#typeof(v.x) == bool)
    #assert(#typeof(v.y) == bool)
    #assert(#typeof(v.z) == string?)

    let v1: MyStruct'f64
    #assert(#typeof(v1.x) == f64)
    #assert(#typeof(v1.y) == f64)
    #assert(#typeof(v1.z) == string?)
}

/**
# Constructing Strings in '#ast'
'#ast' must return a string. You can construct it dynamically, e.g. by using a buffer.
*/
#test
{
    #[Swag.Compiler]
    func append(buf: [*] u8, start: s32, val: string)->s32
    {
        Swag.memcpy(buf + start, val.buffer, cast(u64) val.count)
        return start + cast(s32) val.count
    }

    struct Vector3
    {
        #ast
        {
            var buf: [256] u8
            var len = 0
            len = append(buf, len, "x: f32 = 1\n")
            len = append(buf, len, "y: f32 = 2\n")
            len = append(buf, len, "z: f32 = 3\n")
            return cast(string) Swag.makeSlice(&buf[0], cast(u64) len)
        }
    }

    let v: Vector3
    Swag.assert(v.x == 1)
    Swag.assert(v.y == 2)
    Swag.assert(v.z == 3)
}

/**
# Real-World Example
Example from Std.Core — dynamically generates a struct with all fields of another
struct replaced by bools.

```swag
struct(T) IsSet
{
    #ast
    {
        var str = StrConv.StringBuilder{}
        let typeof = #typeof(T)
        for f in typeof.fields:
            str.appendFormat("%: bool\n", f.name)
        return str.toString()
    }
}
```

*/

/**

# '#ast' at Global Scope

'#ast' can generate global declarations dynamically as well.
*/
#ast
{
    const value = 666
    return "const myGeneratedConst = " ++ value
}

#assert(myGeneratedConst == 666)
