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
