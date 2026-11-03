#global private

#test
{
    var a: s32
    var b: s32
    a, b = 1
    a, b += 1
    Swag.require(a == 2)
    Swag.require(b == 2)
}

#test
{
    var a: s32
    var b: s32
    a, _, b = 1
    Swag.require(a == 1)
    Swag.require(b == 1)
}

#test
{
    var a: f32
    var b: s32
    a, b = 1
    Swag.require(a == 1.0)
    Swag.require(b == 1)
}

#test
{
    var x: u8
    var base = cast([*] u8, &x)
    var a    = base
    a += 1
    a -= 1
    Swag.require(a == base)
}

#test
{
    var data: [3] u16 = [10, 20, 30]
    var ptr           = cast([*] u16, &data[0])
    var count         = 0'u64

    ptr, count += 1
    Swag.require(ptr[] == 20)
    Swag.require(count == 1)

    ptr, count += 1
    Swag.require(ptr[] == 30)
    Swag.require(count == 2)

    ptr, count -= 1
    Swag.require(ptr[] == 20)
    Swag.require(count == 1)
}
