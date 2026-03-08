var Counter: s32
var Seed: s32 = 7
var DropCheck: s32

func fail(code: u32)
{
    var ptr: [*] u8 = null
    ptr[code] = cast(u8) code
}

func check(cond: bool, code: u32)
{
    if !cond
    {
        fail(code)
    }
}

func add(a, b: s32)->s32
{
    return a + b
}

func triple(value: s32)->s32
{
    return add(add(value, value), value)
}

func touch(delta: s32)->s32
{
    Counter += delta
    return Counter
}

func square_plus_seed(value: s32)->s32
{
    return value * value + Seed
}
