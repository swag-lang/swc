#global private

struct FixedPair
{
    a: s32
    b: s32
}

enum FixedKind: u8
{
    A = 5
    B = 9
}

#test
{
    func callOne(?: s32)->s32 { return 41 }
    const V = #run callOne(1)
    #assert(V == 41)
}

#test
{
    func callManyInts(
        ?: s32, ?: s32, ?: s32, ?: s32,
        ?: s32, ?: s32, ?: s32, ?: s32,
        ?: s32, ?: s32, ?: s32, ?: s32)->s32
    {
        return 42
    }

    const V = #run callManyInts(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)
    #assert(V == 42)
}

#test
{
    func callTwo(?: s32, ?: s32)->s32 { return 42 }
    const V = #run callTwo(1, 2)
    #assert(V == 42)
}

#test
{
    func callThree(?: s32, ?: s32, ?: s32)->s32 { return 43 }
    const V = #run callThree(1, 2, 3)
    #assert(V == 43)
}

#test
{
    func callFour(?: s32, ?: s32, ?: s32, ?: s32)->s32 { return 44 }
    const V = #run callFour(1, 2, 3, 4)
    #assert(V == 44)
}

#test
{
    func callFourMixed(?: s32, ?: f32, ?: s64, ?: f64)->s32 { return 45 }
    const V = #run callFourMixed(1, 2.0'f32, 3's64, 4.0'f64)
    #assert(V == 45)
}

#test
{
    func callBoolRune(?: bool, ?: rune, ?: bool, ?: rune)->s32 { return 46 }
    const V = #run callBoolRune(true, 'A', false, 'Z')
    #assert(V == 46)
}

#test
{
    func callFiveInts(?: s32, ?: s32, ?: s32, ?: s32, ?: s32)->s32 { return 47 }
    const V = #run callFiveInts(1, 2, 3, 4, 5)
    #assert(V == 47)
}

#test
{
    func callEightInts(?: s32, ?: s32, ?: s32, ?: s32, ?: s32, ?: s32, ?: s32, ?: s32)->s32 { return 48 }
    const V = #run callEightInts(1, 2, 3, 4, 5, 6, 7, 8)
    #assert(V == 48)
}

#test
{
    func callTenInts(
        ?: s32, ?: s32, ?: s32, ?: s32, ?: s32,
        ?: s32, ?: s32, ?: s32, ?: s32, ?: s32)->s32
    {
        return 49
    }

    const V = #run callTenInts(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
    #assert(V == 49)
}

#test
{
    func callMixedNumeric(
        ?: s32, ?: f32, ?: s32, ?: f32,
        ?: s64, ?: f64, ?: u32, ?: f32,
        ?: u64, ?: f64)->s32
    {
        return 43
    }

    const V = #run callMixedNumeric(1, 2.0'f32, 3, 4.0'f32, 5's64, 6.0'f64, 7'u32, 8.0'f32, 9'u64, 10.0'f64)
    #assert(V == 43)
}

#test
{
    func callSmallInts(?: s8, ?: s16, ?: s32, ?: s64, ?: u8, ?: u16, ?: u32, ?: u64)->s32
    {
        return 44
    }

    const V = #run callSmallInts(-1's8, -2's16, -3's32, -4's64, 5'u8, 6'u16, 7'u32, 8'u64)
    #assert(V == 44)
}

#test
{
    func callBoolRune(?: bool, ?: rune, ?: bool, ?: rune, ?: bool, ?: rune)->s32
    {
        return 45
    }

    const V = #run callBoolRune(true, 'A', false, 'Z', true, '0')
    #assert(V == 45)
}

#test
{
    func tooFew(?: s32, ?: s32)->s32 { return 1 }
    const V = #run tooFew(1)     // swc-expected-error {{sema_err_too_few_arguments}}
}

#test
{
    func tooMany()->s32 { return 1 }
    const V = #run tooMany(1)     // swc-expected-error {{sema_err_too_many_arguments}}
}

#test
{
    func wrongType(?: s32, ?: s32, ?: s32)->s32 { return 1 }
    const V = #run wrongType(1, "bad", 3)     // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    func callAggregate(a: FixedPair, b: [3] s32, c: string)->s32
    {
        return a.a + a.b + b[0] + b[2] + cast(s32, c[1])
    }

    const V = #run callAggregate({a: 2, b: 4}, [10, 20, 30], "Az")
    #assert(V == 168)
}

#test
{
    func callPointerEnum(a: *void?, b: FixedKind, c: s32)->u64
    {
        return cast(u64, (a != null)) + cast(u64, cast(u8, b)) + cast(u64, c)
    }

    const V0 = #run callPointerEnum(null, FixedKind.A, 3)
    const V1 = #run callPointerEnum(cast(*void, 0x45'u64), FixedKind.B, 7)
    #assert(V0 == 8'u64)
    #assert(V1 == 17'u64)
}

#test
{
    func callKindof(a: FixedPair, b: [3] s32, c: string, d: *void, e: FixedKind)->bool
    {
        return #typeof(a) == FixedPair and #typeof(b[0]) == s32 and #typeof(c) == string and #typeof(d) == *void and #typeof(e) == FixedKind
    }

    const V = #run callKindof({a: 1, b: 2}, [3, 4, 5], "ok", cast(*void, 0x10'u64), FixedKind.B)
    #assert(V)
}
