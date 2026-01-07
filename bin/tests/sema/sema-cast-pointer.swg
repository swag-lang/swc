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
