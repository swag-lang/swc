#global internal

func A() {}
func B(x: s32) {}
func C(x: s32, y: s32) {}
func D(x, y: s32 = 0) {}

func D0(me) {}  // swc-expected-error {{sema_err_tok_outside_impl}}
mtd E() {}      // swc-expected-error {{sema_err_method_outside_impl}}

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

namespace NS {}
#test
{
    NS() // swc-expected-error {{sema_err_not_callable}}
}

#test
{
    F0()
    F1(1)
    F0(1) // swc-expected-error {{sema_err_too_many_arguments}}
}

func F0() {}
func F1(x: s32) {}

// swc-expected-error@(+1,+2) {{sema_err_already_defined}}
func F2(a, b, c: s32) {}
func F2(x, y, z: s32) {}


func F4(a: s32 = 0, b: s32) {} // swc-expected-error {{sema_err_parameter_default_value_not_last}}

func F5(a: s32, b: s32 = 0) {}
func F6(a, b: s32 = 0) {}

