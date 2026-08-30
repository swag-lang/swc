#global private

func failAnyCastAssert()->s64
{
    const c: any = 1
    let d = cast(s64) c
    Swag.assert(d == 1)
    Swag.assert(d == 0)     // swc-expected-error {{sema_err_assert_failed}}
    return d
}

#test
{
    const V = #run failAnyCastAssert()
    Swag.assert(V == 1)
}
