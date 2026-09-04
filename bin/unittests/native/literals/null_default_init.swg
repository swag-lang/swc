#global private     //

// null pointer literal
#test
{
    var p: *s32? = null
    #assert(#typeof(p) == *s32?)
    Swag.assert(p == null)
    Swag.assert(!p)
}

// null assignment and comparison
#test
{
    var v: s32   = 42
    var p: *s32? = &v

    Swag.assert(p != null)
    p = null
    Swag.assert(p == null)
}

// null for different pointer types
#test
{
    var a: *u8?   = null
    var b: *f64?  = null
    var c: *void? = null
    Swag.assert(a == null)
    Swag.assert(b == null)
    Swag.assert(c == null)
}

// null optional-style: pointer used as bool
#test
{
    var p: *s32? = null
    Swag.assert(!p)

    var v: s32 = 7
    p = &v
    Swag.assert(p != null)
}

// Default-initialized scalars can be assigned normally before use.
#test
{
    var a: s32
    a = 42
    Swag.assert(a == 42)
}

#test
{
    var a: u64
    a = 0xDEAD_BEEF'u64
    Swag.assert(a == 0xDEAD_BEEF'u64)
}

#test
{
    var a: f64
    a = 3.14'f64
    Swag.assert(a > 3.13'f64 and a < 3.15'f64)
}

// Default-initialized pointer: assign before use.
#test
{
    var a: *s32
    var v: s32 = 99
    a = &v
    Swag.assert(a[] == 99)
}

struct Point { x: s32, y: s32 }

// Struct fields have safe defaults and can be set normally.
#test
{
    struct Vec2 { x: f32, y: f32 }

    var v: Vec2
    v.x = 1.0'f32
    v.y = 2.0'f32
    Swag.assert(v.x == 1.0'f32)
    Swag.assert(v.y == 2.0'f32)
}

// Array elements can be set before reading.
#test
{
    var arr: [3] s32
    arr[0] = 10
    arr[1] = 20
    arr[2] = 30
    Swag.assert(arr[0] == 10)
    Swag.assert(arr[1] == 20)
    Swag.assert(arr[2] == 30)
}
