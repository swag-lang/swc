#global private

#[Swag.DynCast]
struct RequiredCastBase {}
struct RequiredCastChild { using base: RequiredCastBase }

#[Swag.Safety(.DynCast, false), Swag.Safety(.Null, false), Swag.Safety(.Expect, false)]
func requireCast(value: *RequiredCastBase?)->*RequiredCastChild
{
    return expect cast(*RequiredCastChild, value)     // swc-expected-error {{sema_err_compiler_panic}}
}

#test
{
    var value: RequiredCastBase
    discard requireCast(&value)
}

#[Swag.Safety(.Null, false), Swag.Safety(.Expect, false)]
func requirePresentCast(value: *s32?)->*s32
{
    return expect cast(*s32, value)     // swc-expected-error {{sema_err_compiler_panic}}
}

#test
{
    discard requirePresentCast(null)
}
