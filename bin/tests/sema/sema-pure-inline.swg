#global internal

func add(a: s32, b: s32)->s32 => a + b
func mul(a: s32, b: s32)->s32 { return a * b }

#test
{
    #assert(add(2, 3) == 5)
    #assert(mul(4, 5) == 20)
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
