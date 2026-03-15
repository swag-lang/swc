#global fileprivate // swc-option suite-test

func A() {}
func B(x: s32) {}
func C(x: s32, y: s32) {}
func D(x, y: s32 = 0) {}


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
    F0()
    F1(1)
}

#test
{
    A()
    B(10)
    C(1, 2)
    D(1)
    D(1, 2)
    F5(1)
    F5(1, 2)
    F6(1)
    F6(1, 2)
}



func F0() {}
func F1(x: s32) {}



func F5(a: s32, b: s32 = 0) {}
func F6(a, b: s32 = 0) {}
