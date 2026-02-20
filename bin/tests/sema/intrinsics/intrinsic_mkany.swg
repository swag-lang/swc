#global internal

#test
{
    var ptr: *s32
    var b: any = @mkany(ptr, s32)
    var c: any = @mkany(5, s32) // swc-expected-error {{sema_err_expected_type_fam}}
}

#test
{
    var ptr: *s32
    var b: any = @mkany(ptr, ptr) // swc-expected-error {{sema_err_expected_type_fam}}
}

#test
{
    var x: s32
    var y: f32
    var b: any = @mkany(&x, s32)
    var c: any = @mkany(&x, f32) // swc-expected-error {{sema_err_invalid_mkany_ptr}}
    var d: any = @mkany(cast(*void) &x, f32)
}

#test
{
    var y: f32
    var p: *void = cast(*void) &y
    var a: any = @mkany(p, f32)
}

#test
{
    var p: *s32
    var a: any = @mkany(p, f32) // swc-expected-error {{sema_err_invalid_mkany_ptr}}
}
