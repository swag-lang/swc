#global fileprivate //

// null pointer literal
#test
{
    var p: *s32 = null
    #assert(#typeof(p) == *s32)
    @assert(p == null)
    @assert(!p)
}

// null assignment and comparison
#test
{
    var v: s32 = 42
    var p: *s32 = &v

    @assert(p != null)
    p = null
    @assert(p == null)
}

// null for different pointer types
#test
{
    var a: *u8   = null
    var b: *f64  = null
    var c: *void = null
    @assert(a == null)
    @assert(b == null)
    @assert(c == null)
}

// null optional-style: pointer used as bool
#test
{
    var p: *s32 = null
    @assert(!p)

    var v: s32 = 7
    p = &v
    @assert(p != null)
}

// undefined: skip zero-initialization, then assign before use
#test
{
    var a: s32 = undefined
    a = 42
    @assert(a == 42)
}

#test
{
    var a: u64 = undefined
    a = 0xDEAD_BEEF'u64
    @assert(a == 0xDEAD_BEEF'u64)
}

#test
{
    var a: f64 = undefined
    a = 3.14'f64
    @assert(a > 3.13'f64 and a < 3.15'f64)
}

// undefined for pointer: assign before use
#test
{
    var a: *s32 = undefined
    var v: s32 = 99
    a = &v
    @assert(dref a == 99)
}

struct Point { x: s32, y: s32 }

// undefined struct field default: field must be explicitly set
#test
{
    struct Vec2 { x: f32 = undefined, y: f32 = undefined }

    var v: Vec2 = undefined
    v.x = 1.0'f32
    v.y = 2.0'f32
    @assert(v.x == 1.0'f32)
    @assert(v.y == 2.0'f32)
}

// undefined array: elements set before reading
#test
{
    var arr: [3] s32 = undefined
    arr[0] = 10
    arr[1] = 20
    arr[2] = 30
    @assert(arr[0] == 10)
    @assert(arr[1] == 20)
    @assert(arr[2] == 30)
}
