#global internal
/*
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
*/
/*
#test
{
    const Cfg = #run dref @compiler.getBuildCfg()
    #assert(#typeof(Cfg) == Swag.BuildCfg)
//    #assert(Cfg.tempAllocatorCapacity > 0)
}
*/