#global internal

struct AbiPair
{
    a: s32
    b: s32
}

struct AbiPayload
{
    a0: u64
    a1: u64
    a2: u64
    a3: u64
}

alias AbiAlias = s32
enum AbiEnum: u16
{
    A = 17
    B = 123
}

#test
{
    func passString(text: string)->string { return text }
    const V = #run passString("abi-string")
    #assert(V == "abi-string")
    const V1 = #run passString("abi-string-2")
    #assert(V1 == "abi-string-2")
    const V2 = #run passString("abi-string-3")
    #assert(V2 == "abi-string-3")
}

#test
{
    func passString(text: string, idx: s32)->u8 { return text[idx] }
    const V = #run passString("abi-string", 1)
    #assert(V == 98'u8)
    const V1 = #run passString("abi-string", 2)
    #assert(V1 == 'i''u8)
    const V2 = #run passString("abi-string", 9)
    #assert(V2 == 'g''u8)
}

#test
{
    func passArray(values: [4] s32)->[4] s32 { return values }
    const V = #run passArray([11, 22, 33, 44])
    #assert(V[0] == 11)
    #assert(V[3] == 44)
    const V1 = #run passArray([101, 202, 303, 404])
    #assert(V1[0] == 101)
    #assert(V1[3] == 404)
    const V2 = #run passArray([-1, -2, -3, -4])
    #assert(V2[0] == -1)
    #assert(V2[3] == -4)
}

#test
{
    func passPair(value: AbiPair)->AbiPair { return value }
    const V = #run passPair({a: 9, b: 13})
    #assert(V.a == 9)
    #assert(V.b == 13)
    const V1 = #run passPair({a: 91, b: 131})
    #assert(V1.a == 91)
    #assert(V1.b == 131)
    const V2 = #run passPair({a: -9, b: -13})
    #assert(V2.a == -9)
    #assert(V2.b == -13)
}

#test
{
    func passPair(value: AbiPair)->s32 { return value.a + value.b }
    const V = #run passPair({a: 9, b: 13})
    #assert(V == 22)
    const V1 = #run passPair({a: 90, b: 130})
    #assert(V1 == 220)
    const V2 = #run passPair({a: -90, b: 130})
    #assert(V2 == 40)
}

#test
{
    func passPayload(value: AbiPayload)->AbiPayload { return value }
    const V = #run passPayload({a0: 10'u64, a1: 20'u64, a2: 30'u64, a3: 40'u64})
    #assert(V.a0 == 10'u64)
    #assert(V.a3 == 40'u64)
    const V1 = #run passPayload({a0: 100'u64, a1: 200'u64, a2: 300'u64, a3: 400'u64})
    #assert(V1.a0 == 100'u64)
    #assert(V1.a3 == 400'u64)
    const V2 = #run passPayload({a0: 1'u64, a1: 2'u64, a2: 3'u64, a3: 4'u64})
    #assert(V2.a0 == 1'u64)
    #assert(V2.a3 == 4'u64)
}

#test
{
    func passPointer(value: *void)->*void { return value }
    const V = #run passPointer(null)
    #assert(V == null)
    const V1 = #run passPointer(cast(*void) 0x1234'u64)
    #assert(V1 == cast(*void) 0x1234'u64)
    const V2 = #run passPointer(cast(*void) 0xABCD'u64)
    #assert(V2 == cast(*void) 0xABCD'u64)
}

#test
{
    func passMixed(a: s32, b: string, c: AbiPair, d: [2] s32, e: *void)->s32 { return a + c.a + d[1] }
    const V = #run passMixed(3, "mix", {a: 10, b: 11}, [8, 9], null)
    #assert(V == 22)
    const V1 = #run passMixed(30, "mix2", {a: 100, b: 110}, [80, 90], cast(*void) 0x4567'u64)
    #assert(V1 == 220)
    const V2 = #run passMixed(-30, "mix3", {a: 100, b: 110}, [80, 90], cast(*void) 0xFEDC'u64)
    #assert(V2 == 160)
}

#test
{
    func passConstRef(value: const &AbiPair)->s32 { return value.a + value.b }
    const p: AbiPair = {a: 6, b: 7}
    const V = #run passConstRef(p)
    #assert(V == 13)
}

#test
{
    func passScalars(
        a0: s8, a1: s16, a2: s32, a3: s64,
        a4: u8, a5: u16, a6: u32, a7: u64,
        a8: f32, a9: f64, a10: bool, a11: rune)->s32 { return cast(s32) a0 + cast(s32) a1 + a2 + cast(s32) a3 + cast(s32) a4 + cast(s32) a5 + cast(s32) a6 + cast(s32) a7 + cast(s32) a8 + cast(s32) a9 + cast(s32) a10 + cast(s32) a11 }

    const V = #run passScalars(
        -5's8, -123's16, 77's32, 5000's64,
        9'u8, 10'u16, 11'u32, 12'u64,
        1.25'f32, 2.5'f64, true, 'R')
    #assert(V == 5077)
}

#test
{
    func passBoolRunePositions(a: bool, b: s32, c: rune, d: s32, e: bool, f: rune)->s32 { return cast(s32) a + b + cast(s32) c + d + cast(s32) e + cast(s32) f }

    const V = #run passBoolRunePositions(true, 3, 'Q', 4, true, 'W')
    #assert(V == 177)
    const V1 = #run passBoolRunePositions(false, 30, 'Q', 40, false, 'W')
    #assert(V1 == 238)
    const V2 = #run passBoolRunePositions(true, -3, 'Q', 7, false, 'W')
    #assert(V2 == 173)
}

#test
{
    func passAliasEnum(a: s32, b: AbiAlias, c: AbiEnum, d: s32)->s32 { return a + b + cast(s32) cast(u16) c + d }
    const V = #run passAliasEnum(1, 2, AbiEnum.A, 3)
    #assert(V == 23)
    const V1 = #run passAliasEnum(10, 20, AbiEnum.B, 30)
    #assert(V1 == 183)
    const V2 = #run passAliasEnum(-10, 20, AbiEnum.A, -30)
    #assert(V2 == -3)
}

#test
{
    func passSlice(values: [..] s32, idx: s32)->s32 { return values[idx] }
    const values0: [4] s32 = [11, 22, 33, 44]
    const values1: [4] s32 = [101, 202, 303, 404]
    const values2: [4] s32 = [-1, -2, -3, -4]
    const V = #run passSlice(values0, 2)
    #assert(V == 33)
    const V1 = #run passSlice(values1, 3)
    #assert(V1 == 404)
    const V2 = #run passSlice(values2, 0)
    #assert(V2 == -1)
}

//#test
//{
//    func passAggregatePositions(a: *void, b: [2] s32, c: string, d: AbiPair, e: AbiPayload)->u64
//    {
//        return cast(u64) b[1] + cast(u64) d.a + e.a3 + cast(u64) c[0] + cast(u64) (a != null)
//    }
//
//    const V = #run passAggregatePositions(cast(*void) 0x10'u64, [5, 6], "abc", {a: 7, b: 8}, {a0: 1'u64, a1: 2'u64, a2: 3'u64, a3: 4'u64})
//    #assert(V == 114'u64)
//    const V1 = #run passAggregatePositions(null, [50, 60], "Abc", {a: 70, b: 80}, {a0: 10'u64, a1: 20'u64, a2: 30'u64, a3: 40'u64})
//    #assert(V1 == 235'u64)
//}
