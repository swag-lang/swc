#global private

func A() {}
func B(?: s32) {}
func C(?: s32, ?: s32) {}
func D(?, ?: s32 = 0) {}
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

func T1(a0, ?: s32)->s32
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

func TakePoint(?: Point) {}
func TakeSingleString(?: SingleString) {}
func TakeRequiredPoint(?: RequiredPoint) {}
func TakeArray2(?: [2] s32) {}
func TakeMatrix2(?: [2, 2] s32) {}
func TakeArrayU32(?: [2] u32) {}
func TakeByteU8(?: u8) {}

func F0() {}
func F1(?: s32) {}

func F5(?: s32, ?: s32 = 0) {}
func F6(?, ?: s32 = 0) {}
