#global fileprivate

#test
{
    var x: *s32 = null
    var y: const *s32 = null

    var y0 = cast(const *s32) x
    var x0 = cast(*s32) y0 // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var x: const *s32 = null
    var y = cast(*u8) x // swc-expected-error {{sema_err_cannot_cast_const}}
}
