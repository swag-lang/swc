#global internal

#test
{
    var x: *s32 = null
    var y: const *s32 = null

    var y0 = cast(const *s32) x
    #assert(#typeof(y0) == const *s32)
    var x1 = cast #unconst (*s32) y0
    #assert(#typeof(x1) == *s32)
    var x0 = cast(*s32) y0 // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var x: *s32 = null
    var b: [*]s32 = null

    var v: *s32 = b
    #assert(#typeof(v) == *s32)

    var v2 = cast(*s32) b
    #assert(#typeof(v2) == *s32)

    /*var b2: [*]s32 = x // swc-expected-error {{sema_err_cannot_cast}} @compatibility*/
}

#test
{
    var x: *s32 = null
    var b: [*]s32 = null

    var v: *s32 = b
    #assert(#typeof(v) == *s32)

    var v2 = cast(*s32) b
    #assert(#typeof(v2) == *s32)

    var b3 = cast([*]s32) x
    #assert(#typeof(b3) == [*]s32)
}

#test
{
    var x: *s32 = null
    var y = cast(*u8) x
    #assert(#typeof(y) == *u8)
}

#test
{
    var x: *s32 = null
    var y: *u8 = x // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var x: const *s32 = null
    var y = cast(*u8) x // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var x: const *s32 = null
    var y = cast #unconst (*u8) x
    #assert(#typeof(y) == *u8)
}

#test
{
    var x: [*]s32 = null
    var y = cast([*]u8) x
    #assert(#typeof(y) == [*]u8)
}

#test
{
    var x: *s32 = null
    var y = cast([*]u8) x
    #assert(#typeof(y) == [*]u8)

    var x1: u64
    var v1 = cast(*void) x1

    var x2: u32
    var v2 = cast(*void) x2 // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var a: [2] s32
    var p1: *s32 = a
    var p2: const *s32 = a
}

#test
{
    var a: [2] s32
    var p1: *s8 = a // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var a: [2] s32
    var p1: *void = a
}

#test
{
    var str1: string
    let data1 = @dataof(str1)
    let data2: const [*] void = data1
}

#test
{
    var a: typeinfo
    var b = cast(const *u8) a
}