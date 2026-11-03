#global private

#test
{
    var x:   s32
    var ptr: [*] s32 = cast([*] s32, &x)
    ptr += 1
    var ptr1: const [*] s32 = cast(const [*] s32, &x)
    ptr1 += 1
    Swag.require(#typeof(ptr) == [*] s32)
    Swag.require(#typeof(ptr1) == const [*] s32)
}

enum R { A, B }
#test
{
    var a: R
    a = .A
    Swag.require(a == .A)
}

#test
{
    var a: f32
    a += 1's16
    Swag.require(a == 1.0)
}

#test
{
    var a: f32
    a = 1
    Swag.require(a == 1.0)
}

#test
{
    var x: s32
    var p: [*] s32 = cast([*] s32, &x)
    var i: s32
    p += i
    p = p + i
    p = i + p
    p -= 1
    var d: s64
    d = p - p
    Swag.require(d == 0)
}
