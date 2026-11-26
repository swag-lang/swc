#global private

alias PassAlias = s32
enum PassEnum: u16
{
    A = 11
    B = 513
}

struct SmallPair
{
    a: u32
    b: u32
    c: u64
}

struct BigBlob
{
    a0: u64
    a1: u64
    a2: u64
    a3: u64
    a4: u64
}

alias SmallArray = [3] s32
alias BigArray   = [5] s32

#test
{
    func passS8(x: s8) => x
    const V = #run passS8(-12_s8)
    #assert(#typeof(V) == s8)
    #assert(V == -12_s8)
}

#test
{
    func passS16(x: s16) => x
    const V = #run passS16(-1234_s16)
    #assert(#typeof(V) == s16)
    #assert(V == -1234_s16)
}

#test
{
    func passS32(x: s32) => x
    const V = #run passS32(42)
    #assert(#typeof(V) == s32)
    #assert(V == 42)
}

#test
{
    func passS64(x: s64) => x
    const V = #run passS64(5000000000_s64)
    #assert(#typeof(V) == s64)
    #assert(V == 5000000000_s64)
}

#test
{
    func passU8(x: u8) => x
    const V = #run passU8(12_u8)
    #assert(#typeof(V) == u8)
    #assert(V == 12_u8)
}

#test
{
    func passU16(x: u16) => x
    const V = #run passU16(1234_u16)
    #assert(#typeof(V) == u16)
    #assert(V == 1234_u16)
}

#test
{
    func passU32(x: u32) => x
    const V = #run passU32(123456_u32)
    #assert(#typeof(V) == u32)
    #assert(V == 123456_u32)
}

#test
{
    func passU64(x: u64) => x
    const V = #run passU64(5000000000_u64)
    #assert(#typeof(V) == u64)
    #assert(V == 5000000000_u64)
}

#test
{
    func passF32(x: f32) => x
    const V = #run passF32(1.25_f32)
    #assert(#typeof(V) == f32)
    #assert(V == 1.25_f32)
}

#test
{
    func passF64(x: f64) => x
    const V = #run passF64(1.5_f64)
    #assert(#typeof(V) == f64)
    #assert(V == 1.5_f64)
}

#test
{
    func passRune(x: rune) => x
    const V = #run passRune('Z')
    #assert(#typeof(V) == rune)
    #assert(V == 'Z')
}

#test
{
    func passBool(x: bool) => x
    const V = #run passBool(true)
    #assert(#typeof(V) == bool)
    #assert(V == true)
}

#test
{
    func passAlias(x: PassAlias) => x
    const V = #run passAlias(77)
    #assert(#typeof(V) == PassAlias)
    #assert(cast(s32, V) == 77)
}

#test
{
    func passEnum(x: PassEnum) => x
    const V = #run passEnum(PassEnum.B)
    #assert(#typeof(V) == PassEnum)
    #assert(cast(u16, V) == 513_u16)
}

#test
{
    func passString(x: string) => x
    const V = #run passString("run-pass")
    #assert(#typeof(V) == string)
    #assert(V == "run-pass")
}

#test
{
    func passSmallPair(x: SmallPair) => x
    const V = #run passSmallPair({a: 12_u32, b: 34_u32, c: 56_u64})
    #assert(#typeof(V) == SmallPair)
    #assert(V.a == 12_u32)
    #assert(V.b == 34_u32)
    #assert(V.c == 56_u64)
}

#test
{
    func passBigBlob(x: BigBlob) => x
    const V = #run passBigBlob({
        a0: 0x0102_0304_0506_0708_u64,
        a1: 0x1112_1314_1516_1718_u64,
        a2: 0x2122_2324_2526_2728_u64,
        a3: 0x3132_3334_3536_3738_u64,
        a4: 0x4142_4344_4546_4748_u64
        })
    #assert(#typeof(V) == BigBlob)
    #assert(V.a0 == 0x0102_0304_0506_0708_u64)
    #assert(V.a4 == 0x4142_4344_4546_4748_u64)
}

#test
{
    func passSmallArray(x: SmallArray) => x
    const V = #run passSmallArray([12_s32, 34_s32, 56_s32])
    #assert(#typeof(V) == SmallArray)
    #assert(V[0] == 12_s32)
    #assert(V[1] == 34_s32)
    #assert(V[2] == 56_s32)
}

#test
{
    func passBigArray(x: BigArray) => x
    const V = #run passBigArray([1_s32, 2_s32, 3_s32, 4_s32, 5_s32])
    #assert(#typeof(V) == BigArray)
    #assert(V[0] == 1_s32)
    #assert(V[4] == 5_s32)
}

#test
{
    func pickFirst(a: s32, _: s32, _: s32, _: s32, _: s32) => a
    const V = #run pickFirst(11, 22, 33, 44, 55)
    #assert(V == 11)
}

#test
{
    func pickFourth(_: s32, _: s32, _: s32, d: s32) => d
    const V = #run pickFourth(1, 2, 3, 44)
    #assert(V == 44)
}

#test
{
    func pickFifth(_: s32, _: s32, _: s32, _: s32, e: s32) => e
    const V = #run pickFifth(1, 2, 3, 4, 55)
    #assert(V == 55)
}

#test
{
    func pickNinth(
        _: s32, _: s32, _: s32, _: s32, _: s32,
        _: s32, _: s32, _: s32, a8: s32)->s32
    {
        return a8
    }

    const V = #run pickNinth(1, 2, 3, 4, 5, 6, 7, 8, 99)
    #assert(V == 99)
}

#test
{
    func pickFifthF64(_: f64, _: f64, _: f64, _: f64, a4: f64) => a4
    const V = #run pickFifthF64(1.0_f64, 2.0_f64, 3.0_f64, 4.0_f64, 5.5_f64)
    #assert(V == 5.5_f64)
}

#test
{
    func pickSixthF32(_: f32, _: f32, _: f32, _: f32, _: f32, a5: f32) => a5
    const V = #run pickSixthF32(1.0_f32, 2.0_f32, 3.0_f32, 4.0_f32, 5.0_f32, 6.25_f32)
    #assert(V == 6.25_f32)
}

#test
{
    func pickFifthSmall(_: s32, _: s32, _: s32, _: s32, e: SmallPair) => e
    const V = #run pickFifthSmall(1, 2, 3, 4, {a: 88_u32, b: 99_u32, c: 111_u64})
    #assert(V.a == 88_u32)
    #assert(V.b == 99_u32)
    #assert(V.c == 111_u64)
}

#test
{
    func pickSixthBig(_: s32, _: s32, _: s32, _: s32, _: s32, f: BigBlob) => f
    const V = #run pickSixthBig(1, 2, 3, 4, 5, {
        a0: 10_u64,
        a1: 20_u64,
        a2: 30_u64,
        a3: 40_u64,
        a4: 50_u64
        })
    #assert(V.a0 == 10_u64)
    #assert(V.a4 == 50_u64)
}

#test
{
    func pickSeventhString(_: s32, _: s32, _: s32, _: s32, _: s32, _: s32, g: string) => g
    const V = #run pickSeventhString(1, 2, 3, 4, 5, 6, "hello")
    #assert(V == "hello")
}

#test
{
    func pickEighthArray(
        _: s32, _: s32, _: s32, _: s32,
        _: s32, _: s32, _: s32, h: BigArray)->BigArray
    {
        return h
    }

    const V = #run pickEighthArray(1, 2, 3, 4, 5, 6, 7, [7_s32, 8_s32, 9_s32, 10_s32, 11_s32])
    #assert(V[0] == 7_s32)
    #assert(V[4] == 11_s32)
}

#test
{
    func passViaLocal(x: s32)->s32
    {
        var y = x
        return y
    }

    const V = #run passViaLocal(99)
    #assert(V == 99)
}

#test
{
    func passViaLocalBig(x: BigBlob)->BigBlob
    {
        var y = x
        return y
    }

    const V = #run passViaLocalBig({
        a0: 100_u64,
        a1: 200_u64,
        a2: 300_u64,
        a3: 400_u64,
        a4: 500_u64
        })
    #assert(V.a0 == 100_u64)
    #assert(V.a4 == 500_u64)
}

#test
{
    func passPointerFail(x: *void?) => x
    const V = #run passPointerFail(null)
    #assert(#typeof(V) == *void?)
    #assert(V == null)
}

#test
{
    struct TinyPair
    {
        a: u32
        b: u32
    }
    func passTinyPairFail(x: TinyPair) => x
    const V = #run passTinyPairFail({a: 12_u32, b: 34_u32})
    #assert(V.a == 12_u32)
    #assert(V.b == 34_u32)
}

#test
{
    alias TinyArray = [2] s32

    func passTinyArrayFail(x: TinyArray) => x
    const V = #run passTinyArrayFail([12_s32, 34_s32])
    #assert(V[0] == 12_s32)
    #assert(V[1] == 34_s32)
}

#test
{
    func passErr(x: BigBlob) => x
    const V = #run passErr()     // swc-expected-error {{sema_err_too_few_arguments}}
}

#test
{
    func passErr(x: SmallPair) => x
    const V = #run passErr("bad")     // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    func passErr(x: string) => x
    const V = #run passErr("ok", 1)     // swc-expected-error {{sema_err_too_many_arguments}}
}

#test
{
    func passConstRef(x: SmallPair)->u64
    {
        return cast(u64, x.a) + cast(u64, x.b) + x.c
    }

    const P: SmallPair = SmallPair{a: 1_u32, b: 2_u32, c: 39_u64}
    const V = #run passConstRef(P)
    #assert(#typeof(V) == u64)
    #assert(V == 42_u64)
}

#test
{
    func passMixed(a: s32, b: f64, c: string, d: SmallPair, e: PassEnum)->u64
    {
        return cast(u64, a) + cast(u64, b) + cast(u64, c[0]) + d.c + cast(u64, cast(u16, e))
    }

    const V = #run passMixed(1, 2.0_f64, "A", {a: 3_u32, b: 4_u32, c: 5_u64}, PassEnum.A)
    #assert(#typeof(V) == u64)
    #assert(V == 84_u64)
}

#test
{
    func passMixedErr(a: s32, b: SmallPair)->s32 { return a + cast(s32, b.a) }
    const V = #run passMixedErr(1)     // swc-expected-error {{sema_err_too_few_arguments}}
}
