#global private

func semaTest001()
{
    var x: s32
    var ptr: [*] s32 = cast([*] s32) &x
    ptr += 1
    var ptr1: const [*] s32 = cast(const [*] s32) &x
    ptr1 += 1
}

enum R { A, B }
func semaTest002()
{
    var a: R
    a = .A
}

func semaTest003()
{
    var a: f32
    a += 1's16
}

func semaTest004()
{
    var a: f32
    a = 1
}

func semaTest005()
{
    var value:    s32
    var valueRef: &s32 = &value
    valueRef = 42
    valueRef += 1
}

struct AssignRefValue
{
    x: s32
    y: s32
}

func semaTest007()
{
    var value:    AssignRefValue
    var valueRef: &AssignRefValue = &value
    let other:    AssignRefValue = {x: 4, y: 5}
    valueRef = other
}

func semaTest009()
{
    var x: s32
    var p: [*] s32 = cast([*] s32) &x
    var i: s32
    p += i
    p = p + i
    p = i + p
    p -= 1
    var d: s64
    d = p - p
}
