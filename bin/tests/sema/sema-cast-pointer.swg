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

    var b2: [*]s32 = x // swc-expected-error {{sema_err_cannot_cast}}
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
