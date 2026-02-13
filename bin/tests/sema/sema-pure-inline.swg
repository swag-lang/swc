#global internal

func add(a: s32, b: s32)->s32 => a + b
func mul(a: s32, b: s32)->s32 { return a * b }

#test
{
    #assert(add(2, 3) == 5)
    #assert(mul(4, 5) == 20) // swc-expected-error {{sema_err_expr_not_const}}
}

#test
{
    var x: s32 = 3
    #assert(add(x, 1) == 4) // swc-expected-error {{sema_err_expr_not_const}}
}

func wait_inline_const_value()->s32 => WaitInlineConst

#test
{
    #assert(wait_inline_const_value() == 77)
}

#test
{
    #assert(wait_inline_const_value() == 78) // swc-expected-error {{sema_err_compiler_assert}}
}

const WaitInlineConst = 77

func pure_addr(a: s32)->*s32 => &a // swc-expected-error {{sema_err_take_address_constant}}

#test
{
    var x: s32 = 42
    let p = pure_addr(x)
    #assert(#typeof(p) == *s32)
}

#test
{
    let p = pure_addr(1)
}

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
