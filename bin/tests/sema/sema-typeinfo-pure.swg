#global internal

var g: s32

func pureAdd(a: s32, b: s32)->s32
{
    return a + b
}

func impureAdd(a: s32)->s32
{
    return a + g
}

#test
{
    const typePure = cast(const *Swag.TypeInfoFunc) #typeof(pureAdd)
    #assert(typePure.isPure)
}

#test
{
    const typeImpure = cast(const *Swag.TypeInfoFunc) #typeof(impureAdd)
    #assert(!typeImpure.isPure)
}

#test
{
    const typeImpure = cast(const *Swag.TypeInfoFunc) #typeof(impureAdd)
    #assert(typeImpure.isPure) // swc-expected-error {{sema_err_compiler_assert}}
}
