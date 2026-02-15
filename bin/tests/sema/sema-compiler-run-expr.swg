#global internal

struct S
{
    value: s32
}

#test
{
    const V = #run S{42}
    #assert(#typeof(V) == S)
}

#test
{
    const V = #run 40's32 + 2's32
    #assert(#typeof(V) == s32)
    #assert(V == 42)
}

#test
{
    const V = #run 40's32 + 2's32
    #assert(V == 0) // swc-expected-error {{sema_err_compiler_assert}}
}

#test
{
    const V = #run unknownSymbol // swc-expected-error {{sema_err_unknown_symbol}}
}

#test
{
    const V = #run dref @compiler // swc-expected-error {{sema_err_unary_operand_type}}
}

#test
{
    const V = #run dref (@compiler.unknownMethod)() // swc-expected-error {{sema_err_unknown_symbol}}
}

#[Swag.PrintMicro("before-register-allocation", "after-emit")]
#test
{
    const Cfg = #run dref @compiler.getBuildCfg()
    #assert(#typeof(Cfg) == Swag.BuildCfg)
}

#test
{
    const Cfg = #run dref (@compiler.getBuildCfg)()
    #assert(#typeof(Cfg) == Swag.BuildCfg)
}

#test
{
    const Cfg1 = #run dref @compiler.getBuildCfg()
    const Cfg2 = #run dref @compiler.getBuildCfg()
    #assert(#typeof(Cfg1) == Swag.BuildCfg)
    #assert(#typeof(Cfg2) == Swag.BuildCfg)
}

#test
{
    const Cfg = #run dref @compiler.getBuildCfg()
    #assert(#typeof(Cfg) == s32) // swc-expected-error {{sema_err_compiler_assert}}
}

#[Swag.PrintMicro(123)] // swc-expected-error {{sema_err_invalid_type}}
#test
{
    const Cfg = #run dref @compiler.getBuildCfg()
}
