#global private
#global #[Swag.Safety(.Assert, true)]

const Cfg = #run Swag.compiler().getBuildCfg()![]

#test
{
    func passAssert()->s32
    {
        Swag.assert(true)
        return 42
    }

    const V = #run passAssert()
    #assert(V == 42)
}

#test
{
    func failAssert()->s32
    {
        Swag.assert(false)     // swc-expected-error {{sema_err_assert_failed}}
        return 7
    }

    const V = #run failAssert()
    #assert(V == 7)
}

#test
{
    #[Swag.Safety(.Assert, true)]
    func failAssertWithMessage()->s32
    {
        let message = "assertion detail"
        Swag.assert(false, message)     // swc-expected-error {{sema_err_assert_failed}}
        return 0
    }

    const Value = #run failAssertWithMessage()
    #assert(Value == 0)
}
