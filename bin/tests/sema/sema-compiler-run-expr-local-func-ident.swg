#global internal

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
alias BigArray = [5] s32

#test
{
    func passS8(x: s8) => x
    const V = #run passS8(-12's8)
    #assert(#typeof(V) == s8)
    #assert(V == -12's8)
}

#test
{
    func passS16(x: s16) => x
    const V = #run passS16(-1234's16)
    #assert(#typeof(V) == s16)
    #assert(V == -1234's16)
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
    const V = #run passS64(5000000000's64)
    #assert(#typeof(V) == s64)
    #assert(V == 5000000000's64)
}

#test
{
    func passU8(x: u8) => x
    const V = #run passU8(12'u8)
    #assert(#typeof(V) == u8)
    #assert(V == 12'u8)
}

#test
{
    func passU16(x: u16) => x
    const V = #run passU16(1234'u16)
    #assert(#typeof(V) == u16)
    #assert(V == 1234'u16)
}

#test
{
    func passU32(x: u32) => x
    const V = #run passU32(123456'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 123456'u32)
}

#test
{
    func passU64(x: u64) => x
    const V = #run passU64(5000000000'u64)
    #assert(#typeof(V) == u64)
    #assert(V == 5000000000'u64)
}

#test
{
    func passF32(x: f32) => x
    const V = #run passF32(1.25'f32)
    #assert(#typeof(V) == f32)
    #assert(V == 1.25'f32)
}

#test
{
    func passF64(x: f64) => x
    const V = #run passF64(1.5'f64)
    #assert(#typeof(V) == f64)
    #assert(V == 1.5'f64)
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
    #assert(cast(s32) V == 77)
}

#test
{
    func passEnum(x: PassEnum) => x
    const V = #run passEnum(PassEnum.B)
    #assert(#typeof(V) == PassEnum)
    #assert(cast(u16) V == 513'u16)
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
    const V = #run passSmallPair({a: 12'u32, b: 34'u32, c: 56'u64})
    #assert(#typeof(V) == SmallPair)
    #assert(V.a == 12'u32)
    #assert(V.b == 34'u32)
    #assert(V.c == 56'u64)
}

#test
{
    func passBigBlob(x: BigBlob) => x
    const V = #run passBigBlob({
        a0: 0x0102_0304_0506_0708'u64,
        a1: 0x1112_1314_1516_1718'u64,
        a2: 0x2122_2324_2526_2728'u64,
        a3: 0x3132_3334_3536_3738'u64,
        a4: 0x4142_4344_4546_4748'u64,
    })
    #assert(#typeof(V) == BigBlob)
    #assert(V.a0 == 0x0102_0304_0506_0708'u64)
    #assert(V.a4 == 0x4142_4344_4546_4748'u64)
}

#test
{
    func passSmallArray(x: SmallArray) => x
    const V = #run passSmallArray([12's32, 34's32, 56's32])
    #assert(#typeof(V) == SmallArray)
    #assert(V[0] == 12's32)
    #assert(V[1] == 34's32)
    #assert(V[2] == 56's32)
}

#test
{
    func passBigArray(x: BigArray) => x
    const V = #run passBigArray([1's32, 2's32, 3's32, 4's32, 5's32])
    #assert(#typeof(V) == BigArray)
    #assert(V[0] == 1's32)
    #assert(V[4] == 5's32)
}

#test
{
    func pickFirst(a: s32, b: s32, c: s32, d: s32, e: s32) => a
    const V = #run pickFirst(11, 22, 33, 44, 55)
    #assert(V == 11)
}

#test
{
    func pickFourth(a: s32, b: s32, c: s32, d: s32) => d
    const V = #run pickFourth(1, 2, 3, 44)
    #assert(V == 44)
}

#test
{
    func pickFifth(a: s32, b: s32, c: s32, d: s32, e: s32) => e
    const V = #run pickFifth(1, 2, 3, 4, 55)
    #assert(V == 55)
}

#test
{
    func pickNinth(
        a0: s32, a1: s32, a2: s32, a3: s32, a4: s32,
        a5: s32, a6: s32, a7: s32, a8: s32)->s32
    {
        return a8
    }

    const V = #run pickNinth(1, 2, 3, 4, 5, 6, 7, 8, 99)
    #assert(V == 99)
}

#test
{
    func pickFifthF64(a0: f64, a1: f64, a2: f64, a3: f64, a4: f64) => a4
    const V = #run pickFifthF64(1.0'f64, 2.0'f64, 3.0'f64, 4.0'f64, 5.5'f64)
    #assert(V == 5.5'f64)
}

#test
{
    func pickSixthF32(a0: f32, a1: f32, a2: f32, a3: f32, a4: f32, a5: f32) => a5
    const V = #run pickSixthF32(1.0'f32, 2.0'f32, 3.0'f32, 4.0'f32, 5.0'f32, 6.25'f32)
    #assert(V == 6.25'f32)
}

#test
{
    func pickFifthSmall(a: s32, b: s32, c: s32, d: s32, e: SmallPair) => e
    const V = #run pickFifthSmall(1, 2, 3, 4, {a: 88'u32, b: 99'u32, c: 111'u64})
    #assert(V.a == 88'u32)
    #assert(V.b == 99'u32)
    #assert(V.c == 111'u64)
}

#test
{
    func pickSixthBig(a: s32, b: s32, c: s32, d: s32, e: s32, f: BigBlob) => f
    const V = #run pickSixthBig(1, 2, 3, 4, 5, {
        a0: 10'u64,
        a1: 20'u64,
        a2: 30'u64,
        a3: 40'u64,
        a4: 50'u64,
    })
    #assert(V.a0 == 10'u64)
    #assert(V.a4 == 50'u64)
}

#test
{
    func pickSeventhString(a: s32, b: s32, c: s32, d: s32, e: s32, f: s32, g: string) => g
    const V = #run pickSeventhString(1, 2, 3, 4, 5, 6, "hello")
    #assert(V == "hello")
}

#test
{
    func pickEighthArray(
        a: s32, b: s32, c: s32, d: s32,
        e: s32, f: s32, g: s32, h: BigArray)->BigArray
    {
        return h
    }

    const V = #run pickEighthArray(1, 2, 3, 4, 5, 6, 7, [7's32, 8's32, 9's32, 10's32, 11's32])
    #assert(V[0] == 7's32)
    #assert(V[4] == 11's32)
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
        a0: 100'u64,
        a1: 200'u64,
        a2: 300'u64,
        a3: 400'u64,
        a4: 500'u64,
    })
    #assert(V.a0 == 100'u64)
    #assert(V.a4 == 500'u64)
}

#test
{
    func passErr(x: BigBlob) => x
    const V = #run passErr() // swc-expected-error {{sema_err_too_few_arguments}}
}

#test
{
    func passErr(x: SmallPair) => x
    const V = #run passErr("bad") // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    func passErr(x: string) => x
    const V = #run passErr("ok", 1) // swc-expected-error {{sema_err_too_many_arguments}}
}

#test
{
    func passPointerFail(x: *void) => x
    const V = #run passPointerFail(null)
    #assert(#typeof(V) == *void)
    #assert(V == null)
}

// #test
// {
//     struct TinyPair
//     {
//         a: u32
//         b: u32
//     }
//
//     func passTinyPairFail(x: TinyPair) => x
//     const V = #run passTinyPairFail({a: 12'u32, b: 34'u32})
//     #assert(V.a == 12'u32)
//     #assert(V.b == 34'u32)
// }
//
// #test
// {
//     alias TinyArray = [2] s32
//
//     func passTinyArrayFail(x: TinyArray) => x
//     const V = #run passTinyArrayFail([12's32, 34's32])
//     #assert(V[0] == 12's32)
//     #assert(V[1] == 34's32)
// }
