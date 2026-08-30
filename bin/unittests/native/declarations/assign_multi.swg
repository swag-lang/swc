#global private

#test
{
    var a: s32
    var b: s32
    a, b = 1
    a, b += 1
    Swag.assert(a == 2)
    Swag.assert(b == 2)
}

#test
{
    var a: s32
    var b: s32
    a, ?, b = 1
    Swag.assert(a == 1)
    Swag.assert(b == 1)
}

#test
{
    var a: f32
    var b: s32
    a, b = 1
    Swag.assert(a == 1.0)
    Swag.assert(b == 1)
}

#test
{
    var x: u8
    var base = cast([*] u8) &x
    var a    = base
    a += 1
    a -= 1
    Swag.assert(a == base)
}

#test
{
    var data: [3] u16 = [10, 20, 30]
    var ptr           = cast([*] u16) &data[0]
    var count         = 0'u64

    ptr, count += 1
    Swag.assert(ptr[] == 20)
    Swag.assert(count == 1)

    ptr, count += 1
    Swag.assert(ptr[] == 30)
    Swag.assert(count == 2)

    ptr, count -= 1
    Swag.assert(ptr[] == 20)
    Swag.assert(count == 1)
}
