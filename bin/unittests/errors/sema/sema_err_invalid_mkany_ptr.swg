#global private

#test
{
    var x: s32
    var y: f32
    var c: any = Swag.makeAny(&x, f32)     // swc-expected-error {{sema_err_invalid_mkany_ptr}}
}

#test
{
    var p: *s32?
    var a: any = Swag.makeAny(p, f32)     // swc-expected-error {{sema_err_invalid_mkany_ptr}}
}

#test
{
    var p: [*] s32?
    var a: any = Swag.makeAny(p, f32)     // swc-expected-error {{sema_err_invalid_mkany_ptr}}
}
