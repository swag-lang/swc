#global fileprivate // swc-option suite-jit

func failAnyCastAssert()->s64
{
    const c: any = 1
    let d = cast(s64) c
    @assert(d == 1)
    @assert(d == 0) // swc-expected-error {{sema_err_assert_failed}}
    return d
}

#test
{
    const V = #run failAnyCastAssert()
    @assert(V == 1)
}
