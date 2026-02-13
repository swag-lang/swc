#global internal

var g: s32

func shortPure(a: s32, b: s32)->s32 => a + b
func shortImpureGlobal(a: s32)->s32 => a + g
func helper(a: s32)->s32 { return a + 1 }
func shortImpureCall(a: s32)->s32 => helper(a)
func longPureStyle(a: s32)->s32 { return a + 1 }

#test
{
    const typeShortPure = cast(const *Swag.TypeInfoFunc) #typeof(shortPure)
    #assert((typeShortPure.flags & .Pure) != 0)
}

#test
{
    const typeShortImpureGlobal = cast(const *Swag.TypeInfoFunc) #typeof(shortImpureGlobal)
    #assert((typeShortImpureGlobal.flags & .Pure) == 0)
}

#test
{
    const typeShortImpureCall = cast(const *Swag.TypeInfoFunc) #typeof(shortImpureCall)
    #assert((typeShortImpureCall.flags & .Pure) == 0)
}

#test
{
    const typeLongPureStyle = cast(const *Swag.TypeInfoFunc) #typeof(longPureStyle)
    #assert((typeLongPureStyle.flags & .Pure) == 0)
}

#test
{
    const typeShortPure = cast(const *Swag.TypeInfoFunc) #typeof(shortPure)
    #assert((typeShortPure.flags & .Pure) == 0) // swc-expected-error {{sema_err_compiler_assert}}
}

#test
{
    const typeLongPureStyle = cast(const *Swag.TypeInfoFunc) #typeof(longPureStyle)
    #assert((typeLongPureStyle.flags & .Pure) != 0) // swc-expected-error {{sema_err_compiler_assert}}
}
