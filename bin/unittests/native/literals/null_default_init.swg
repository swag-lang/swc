#global private     //

// null pointer literal
#test
{
    var p: *s32? = null
    #assert(#typeof(p) == *s32?)
    Swag.require(p == null)
    Swag.require(not p)
}

// null assignment and comparison
#test
{
    var v: s32   = 42
    var p: *s32? = &v

    Swag.require(p != null)
    p = null
    Swag.require(p == null)
}

// null for different pointer types
#test
{
    var a: *u8?   = null
    var b: *f64?  = null
    var c: *void? = null
    Swag.require(a == null)
    Swag.require(b == null)
    Swag.require(c == null)
}

// null optional-style: pointer used as bool
#test
{
    var p: *s32? = null
    Swag.require(not p)

    var v: s32 = 7
    p = &v
    Swag.require(p != null)
}

// Default-initialized scalars can be assigned normally before use.
#test
{
    var a: s32
    a = 42
    Swag.require(a == 42)
}

#test
{
    var a: u64
    a = 0xDEAD_BEEF'u64
    Swag.require(a == 0xDEAD_BEEF'u64)
}

#test
{
    var a: f64
    a = 3.14'f64
    Swag.require(a > 3.13'f64 and a < 3.15'f64)
}

// Default-initialized pointer: assign before use.
#test
{
    var a: *s32
    var v: s32 = 99
    a = &v
    Swag.require(a[] == 99)
}

struct Point { x: s32, y: s32 }

// Struct fields have safe defaults and can be set normally.
#test
{
    struct Vec2 { x: f32, y: f32 }

    var v: Vec2
    v.x = 1.0'f32
    v.y = 2.0'f32
    Swag.require(v.x == 1.0'f32)
    Swag.require(v.y == 2.0'f32)
}

// Array elements can be set before reading.
#test
{
    var arr: [3] s32
    arr[0] = 10
    arr[1] = 20
    arr[2] = 30
    Swag.require(arr[0] == 10)
    Swag.require(arr[1] == 20)
    Swag.require(arr[2] == 30)
}
