#global private

func A() {}
func B(_: s32) {}
func C(_: s32, _: s32) {}
func D(_, _: s32 = 0) {}
struct Point
{
    x: s32
    y: s32
}
struct SingleInt
{
    value: s32
}
struct SingleString
{
    value: string
}
struct RequiredPoint
{
    x: s32
    y: s32 = 5
    z: s32
}

func T()->s32
{
    let a = T()
    return a
}

func T1(a0, _: s32)->s32
{
    let c = a0
    return c
}

namespace NS {}

func semaTest001()
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

func TakePoint(_: Point) {}
func TakeSingleString(_: SingleString) {}
func TakeRequiredPoint(_: RequiredPoint) {}
func TakeArray2(_: [2] s32) {}
func TakeMatrix2(_: [2, 2] s32) {}
func TakeArrayU32(_: [2] u32) {}
func TakeByteU8(_: u8) {}

func F0() {}
func F1(_: s32) {}

func F5(_: s32, _: s32 = 0) {}
func F6(_, _: s32 = 0) {}
