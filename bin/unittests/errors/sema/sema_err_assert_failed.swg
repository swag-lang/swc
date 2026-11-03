#global private
#global #[Swag.Safety(.Assert, true)]

func failAnyCastAssert()->s64
{
    const c: any = 1's64
    let d = assume cast(s64, c)
    Swag.assert(d == 1)
    Swag.assert(d == 0)     // swc-expected-error {{sema_err_assert_failed}}
    return d
}

// A requirement is a test verdict: disabling assertions does not remove it.
#[Swag.Safety(.Assert, false)]
func failRequireWithoutAssertions()->s64
{
    Swag.require(1 + 1 == 3)     // swc-expected-error {{sema_err_assert_failed}}
    return 0
}

#test
{
    const V = #run failAnyCastAssert()
    Swag.require(V == 1)
}

#test
{
    const W = #run failRequireWithoutAssertions()
    Swag.require(W == 0)
}
