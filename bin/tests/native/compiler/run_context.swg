// swc-option suite-test

#global fileprivate

func contextStackMixA(a: s32, b: s32, c: s32, d: s32, e: s32, f: s32)->s32
{
    return a + b + c + d + e + f
}

func contextStackMixB(a: s32, b: s32, c: s32, d: s32, e: s32, f: s32, g: s32, h: s32, i: s32, j: s32)->s32
{
    return a + b + c + d + e + f + g + h + i + j
}

#test
{
    var a = contextStackMixA(1, 2, 3, 4, 5, 6)
    var b = contextStackMixB(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
    @assert(a + b == 76)
}
