#global internal

func A() {}
func B(x: s32) {}
func C(x: s32, y: s32) {}
func D(x, y: s32 = 0) {}

func D0(me) {} // swc-expected-error {{sema_err_tok_outside_impl}}
mtd E() {} // swc-expected-error {{sema_err_method_outside_impl}}

func T()->s32
{
    let a = T()
    return a
}

func T1(a0, b0: s32)->s32
{
    let c = a0
    return c
}
