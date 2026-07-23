#global private

#test
{
    var x: s32
    var y: f32
    var c: any = @mkany(&x, f32)     // swc-expected-error {{sema_err_invalid_mkany_ptr}}
}

#test
{
    var p: #null *s32
    var a: any = @mkany(p, f32)     // swc-expected-error {{sema_err_invalid_mkany_ptr}}
}

#test
{
    var p: #null [*] s32
    var a: any = @mkany(p, f32)     // swc-expected-error {{sema_err_invalid_mkany_ptr}}
}
