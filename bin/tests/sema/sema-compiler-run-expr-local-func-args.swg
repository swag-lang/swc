#global internal

#test
{
    func callOne(a: s32)->s32 { return 41 }
    const V = #run callOne(1)
    #assert(V == 41)
}

#test
{
    func callManyInts(
        a0: s32, a1: s32, a2: s32, a3: s32,
        a4: s32, a5: s32, a6: s32, a7: s32,
        a8: s32, a9: s32, a10: s32, a11: s32)->s32
    {
        return 42
    }

    const V = #run callManyInts(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)
    #assert(V == 42)
}

#test
{
    func callTwo(a: s32, b: s32)->s32 { return 42 }
    const V = #run callTwo(1, 2)
    #assert(V == 42)
}

#test
{
    func callThree(a: s32, b: s32, c: s32)->s32 { return 43 }
    const V = #run callThree(1, 2, 3)
    #assert(V == 43)
}

#test
{
    func callFour(a: s32, b: s32, c: s32, d: s32)->s32 { return 44 }
    const V = #run callFour(1, 2, 3, 4)
    #assert(V == 44)
}

#test
{
    func callFourMixed(a: s32, b: f32, c: s64, d: f64)->s32 { return 45 }
    const V = #run callFourMixed(1, 2.0'f32, 3's64, 4.0'f64)
    #assert(V == 45)
}

#test
{
    func callBoolRune(a: bool, b: rune, c: bool, d: rune)->s32 { return 46 }
    const V = #run callBoolRune(true, 'A', false, 'Z')
    #assert(V == 46)
}

#test
{
    func callFiveInts(a: s32, b: s32, c: s32, d: s32, e: s32)->s32 { return 47 }
    const V = #run callFiveInts(1, 2, 3, 4, 5)
    #assert(V == 47)
}

#test
{
    func callEightInts(a0: s32, a1: s32, a2: s32, a3: s32, a4: s32, a5: s32, a6: s32, a7: s32)->s32 { return 48 }
    const V = #run callEightInts(1, 2, 3, 4, 5, 6, 7, 8)
    #assert(V == 48)
}

#test
{
    func callTenInts(
        a0: s32, a1: s32, a2: s32, a3: s32, a4: s32,
        a5: s32, a6: s32, a7: s32, a8: s32, a9: s32)->s32
    {
        return 49
    }

    const V = #run callTenInts(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
    #assert(V == 49)
}

#test
{
    func callMixedNumeric(
        a0: s32, a1: f32, a2: s32, a3: f32,
        a4: s64, a5: f64, a6: u32, a7: f32,
        a8: u64, a9: f64)->s32
    {
        return 43
    }

    const V = #run callMixedNumeric(1, 2.0'f32, 3, 4.0'f32, 5's64, 6.0'f64, 7'u32, 8.0'f32, 9'u64, 10.0'f64)
    #assert(V == 43)
}

#test
{
    func callSmallInts(a: s8, b: s16, c: s32, d: s64, e: u8, f: u16, g: u32, h: u64)->s32
    {
        return 44
    }

    const V = #run callSmallInts(-1's8, -2's16, -3's32, -4's64, 5'u8, 6'u16, 7'u32, 8'u64)
    #assert(V == 44)
}

#test
{
    func callBoolRune(a: bool, b: rune, c: bool, d: rune, e: bool, f: rune)->s32
    {
        return 45
    }

    const V = #run callBoolRune(true, 'A', false, 'Z', true, '0')
    #assert(V == 45)
}

#test
{
    func tooFew(a: s32, b: s32)->s32 { return 1 }
    const V = #run tooFew(1) // swc-expected-error {{sema_err_too_few_arguments}}
}

#test
{
    func tooMany()->s32 { return 1 }
    const V = #run tooMany(1) // swc-expected-error {{sema_err_too_many_arguments}}
}

#test
{
    func wrongType(a: s32, b: s32, c: s32)->s32 { return 1 }
    const V = #run wrongType(1, "bad", 3) // swc-expected-error {{sema_err_cannot_cast}}
}
