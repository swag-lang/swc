#global fileprivate // 

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

func callOne(a: s32)->s32
{
    return a + 40
}

func callManyInts(
    a0: s32, a1: s32, a2: s32, a3: s32,
    a4: s32, a5: s32, a6: s32, a7: s32,
    a8: s32, a9: s32, a10: s32, a11: s32)->s32
{
    return a0 + a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8 + a9 + a10 + a11
}

func callMixedNumeric(
    a0: s32, a1: f32, a2: s32, a3: f32,
    a4: s64, a5: f64, a6: u32, a7: f32,
    a8: u64, a9: f64)->s64
{
    return cast(s64) a0 + cast(s64) a1 + cast(s64) a2 + cast(s64) a3 + a4 + cast(s64) a5 + cast(s64) a6 + cast(s64) a7 + cast(s64) a8 + cast(s64) a9
}

func callSmallInts(a: s8, b: s16, c: s32, d: s64, e: u8, f: u16, g: u32, h: u64)->s64
{
    return cast(s64) a + cast(s64) b + cast(s64) c + d + cast(s64) e + cast(s64) f + cast(s64) g + cast(s64) h
}

func callBoolRune(a: bool, b: rune, c: bool, d: rune, e: bool, f: rune)->s32
{
    return cast(s32) a + cast(s32) b + cast(s32) c + cast(s32) d + cast(s32) e + cast(s32) f
}

func callAggregate(a: FixedPair, b: [3] s32, c: string)->s32
{
    return a.a + a.b + b[0] + b[2] + cast(s32) c[1]
}

func callPointerEnum(a: *void, b: FixedKind, c: s32)->u64
{
    return cast(u64) (a != null) + cast(u64) cast(u8) b + cast(u64) c
}

func callKindof(a: FixedPair, b: [3] s32, c: string, d: *void, e: FixedKind)->bool
{
    return #typeof(a) == FixedPair and #typeof(b[0]) == s32 and #typeof(c) == string and #typeof(d) == *void and #typeof(e) == FixedKind
}

#test
{
    @assert(callOne(1) == 41)
    @assert(callManyInts(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12) == 78)
    @assert(callManyInts(10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120) == 780)
}

#test
{
    let mixed = callMixedNumeric(1, 2.0'f32, 3, 4.0'f32, 5's64, 6.0'f64, 7'u32, 8.0'f32, 9'u64, 10.0'f64)
    let small = callSmallInts(-1's8, -2's16, -3's32, -4's64, 5'u8, 6'u16, 7'u32, 8'u64)
    let rune0 = callBoolRune(true, 'A', false, 'Z', true, '0')
    let rune1 = callBoolRune(false, 'B', true, 'C', false, 'D')

    #assert(#typeof(mixed) == s64)
    #assert(#typeof(small) == s64)
    #assert(#typeof(rune0) == s32)

    @assert(mixed == 55's64)
    @assert(small == 16's64)
    @assert(rune0 == 205)
    @assert(rune1 == 202)
}

#test
{
    let sum0 = callAggregate({a: 2, b: 4}, [10, 20, 30], "Az")
    let sum1 = callAggregate({a: -2, b: 14}, [4, 5, 6], "By")
    let ptr0 = callPointerEnum(null, FixedKind.A, 3)
    let ptr1 = callPointerEnum(cast(*void) 0x45'u64, FixedKind.B, 7)

    #assert(#typeof(ptr0) == u64)
    @assert(sum0 == 168)
    @assert(sum1 == 143)
    @assert(ptr0 == 8'u64)
    @assert(ptr1 == 17'u64)
    @assert(callKindof({a: 1, b: 2}, [3, 4, 5], "ok", cast(*void) 0x10'u64, FixedKind.B))
}
