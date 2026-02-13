#global internal

func add(a: s32, b: s32)->s32 => a + b

#[Swag.Inline]
func addInline(a: s32, b: s32)->s32 => a + b

#[Swag.Inline]
func mulInline(a: s32, b: s32)->s32 { return a * b }

func helper(a: s32)->s32 { return a + 1 }

#[Swag.Inline]
func inlineCallsNonConst(a: s32)->s32 => helper(a)

#test
{
    #assert(addInline(2, 3) == 5)
    #assert(mulInline(4, 5) == 20)
}

#test
{
    #assert(add(2, 3) == 5) // swc-expected-error {{sema_err_expr_not_const}}
}

#test
{
    var x: s32 = 3
    #assert(addInline(x, 1) == 4) // swc-expected-error {{sema_err_expr_not_const}}
}

#test
{
    #assert(inlineCallsNonConst(2) == 3) // swc-expected-error {{sema_err_expr_not_const}}
}
