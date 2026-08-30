#global private

#[Swag.Compiler]
func failJitFlag()->s32
{
    Swag.assert(Swag.jit())
    Swag.assert(!Swag.jit())     // swc-expected-error {{sema_err_assert_failed}}
    return 1
}

#[Swag.Compiler]
func failContextSum()->s32
{
    let a = 1 + 2 + 3 + 4 + 5 + 6
    let b = 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10
    Swag.assert(a + b == 0)     // swc-expected-error {{sema_err_assert_failed}}
    return a + b
}

#test
{
    const V = #run failJitFlag()
    Swag.assert(V == 1)
}

#test
{
    const V = #run failContextSum()
    Swag.assert(V == 76)
}
