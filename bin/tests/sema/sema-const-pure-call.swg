#global internal

#test
{
    func add(a: s32, b: s32) -> s32 => a + b
    const A: s32 = add(1, 2)
    #assert(A == 3)
}

#test
{
    func add(a: s32, b: s32) -> s32 => a + b
    var v: s32 = 2
    const B: s32 = add(1, v) // swc-expected-error {{sema_err_expr_not_const}}
}

#test
{
    var g: s32 = 1
    func impure(a: s32) -> s32 => a + g
    const C: s32 = impure(1) // swc-expected-error {{sema_err_expr_not_const}}
}
