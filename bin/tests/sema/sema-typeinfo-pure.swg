#global internal

var g: s32

func pureAdd(a: s32, b: s32)->s32 { return a + b }
func impureAdd(a: s32)->s32 { return a + g }
func impureWrite(a: s32)->s32 { g = a; return g }
func pureLocal()->s32 { var x: s32 = 1; return x + 2 }

#test
{
    const typePure = cast(const *Swag.TypeInfoFunc) #typeof(pureAdd)
    #assert((typePure.flags & .Pure) != 0)
}

#test
{
    const typeImpure = cast(const *Swag.TypeInfoFunc) #typeof(impureAdd)
    #assert((typeImpure.flags & .Pure) == 0)
}

#test
{
    const typeImpure = cast(const *Swag.TypeInfoFunc) #typeof(impureAdd)
    #assert((typeImpure.flags & .Pure) != 0) // swc-expected-error {{sema_err_compiler_assert}}
}

#test
{
    const typePure = cast(const *Swag.TypeInfoFunc) #typeof(pureLocal)
    #assert((typePure.flags & .Pure) == 0)
}
