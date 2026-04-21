#global fileprivate

#test
{
    var ptr: [*] s32
    ptr += 1
    var ptr1: const [*] s32
    ptr1 += 1
}

enum R { A, B }
#test
{
    var a: R
    a = .A
}

#test
{
    var a: f32
    a += 1's16
}

#test
{
    var a: f32
    a = 1
}

#test
{
    var value: s32
    var valueRef: &s32 = &value
    valueRef = 42
    valueRef += 1
}

#test
{
    var left: s32
    var right: s32
    var valueRef: &s32 = &left
    valueRef = #ref &right
    valueRef = 42
}

struct AssignRefValue
{
    x: s32
    y: s32
}

#test
{
    var value: AssignRefValue
    var valueRef: &AssignRefValue = &value
    let other: AssignRefValue = {x: 4, y: 5}
    valueRef = other
}

#test
{
    var left: AssignRefValue
    var right: AssignRefValue
    var valueRef: &AssignRefValue = &left
    valueRef = #ref &right
    valueRef = {x: 4, y: 5}
}

#test
{
    var p: [*] s32
    var i: s32
    p += i
    p = p + i
    p = i + p
    p -= 1
    var d: s64
    d = p - p
}
