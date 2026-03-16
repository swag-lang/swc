#global fileprivate // swc-option suite-jit

func failJitFlag()->s32
{
    @assert(@jit)
    @assert(!@jit) // swc-expected-error {{sema_err_assert_failed}}
    return 1
}

func failContextSum()->s32
{
    let a = 1 + 2 + 3 + 4 + 5 + 6
    let b = 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10
    @assert(a + b == 0) // swc-expected-error {{sema_err_assert_failed}}
    return a + b
}

#test
{
    const V = #run failJitFlag()
    @assert(V == 1)
}

#test
{
    const V = #run failContextSum()
    @assert(V == 76)
}
