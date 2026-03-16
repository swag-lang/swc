#global fileprivate // swc-option suite-test

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

struct AbiNested
{
    p: AbiPair
    q: AbiPayload
}

func passString(text: string)->string
{
    return text
}

func passStringAt(text: string, idx: s32)->u8
{
    return text[idx]
}

func passArray(values: [4] s32)->[4] s32
{
    return values
}

func passPair(value: AbiPair)->AbiPair
{
    return value
}

func passPairSum(value: AbiPair)->s32
{
    return value.a + value.b
}

func passPayload(value: AbiPayload)->AbiPayload
{
    return value
}

func passPointer(value: *void)->*void
{
    return value
}

func passMixed(a: s32, b: string, c: AbiPair, d: [2] s32, e: *void)->s32
{
    return a + cast(s32) b[0] + c.a + d[1] + cast(s32) (e != null)
}

func passConstRef(value: const &AbiPair)->s32
{
    return value.a + value.b
}

func passScalars(
    a0: s8, a1: s16, a2: s32, a3: s64,
    a4: u8, a5: u16, a6: u32, a7: u64,
    a8: f32, a9: f64, a10: bool, a11: rune)->s32
{
    return cast(s32) a0 + cast(s32) a1 + a2 + cast(s32) a3 + cast(s32) a4 + cast(s32) a5 + cast(s32) a6 + cast(s32) a7 + cast(s32) a8 + cast(s32) a9 + cast(s32) a10 + cast(s32) a11
}

func passBoolRunePositions(a: bool, b: s32, c: rune, d: s32, e: bool, f: rune)->s32
{
    return cast(s32) a + b + cast(s32) c + d + cast(s32) e + cast(s32) f
}

func passAliasEnum(a: s32, b: AbiAlias, c: AbiEnum, d: s32)->s32
{
    return a + b + cast(s32) cast(u16) c + d
}

func passSlice(values: [..] s32, idx: s32)->s32
{
    return values[idx]
}

func passAggregatePositions(a: *void, b: [2] s32, c: string, d: AbiPair, e: AbiPayload)->u64
{
    return cast(u64) b[1] + cast(u64) d.a + e.a3 + cast(u64) c[0] + cast(u64) (a != null)
}

func passNested(value: AbiNested, extra: s32)->u64
{
    return cast(u64) value.p.a + cast(u64) value.p.b + value.q.a0 + value.q.a3 + cast(u64) extra
}

func passKindof(value: AbiPair, payload: AbiPayload, text: string, p: *void, values: [2] s32, e: AbiEnum)->bool
{
    return #typeof(value) == AbiPair and #typeof(payload) == AbiPayload and #typeof(text) == string and #typeof(p) == *void and #typeof(values[1]) == s32 and #typeof(e) == AbiEnum
}

func passNestedArray(value: AbiNested, array0: [2] AbiPair)->s32
{
    return value.p.a + array0[0].b + array0[1].a
}

#test
{
    @assert(passString("abi-string") == "abi-string")
    @assert(passString("abi-string-2") == "abi-string-2")
    @assert(passStringAt("abi-string", 1) == 98'u8)
    @assert(passStringAt("abi-string", 2) == 'i''u8)
    @assert(passStringAt("abi-string", 9) == 'g''u8)

    let array0 = passArray([11, 22, 33, 44])
    let array1 = passArray([101, 202, 303, 404])
    let array2 = passArray([-1, -2, -3, -4])
    @assert(array0[0] == 11)
    @assert(array0[3] == 44)
    @assert(array1[0] == 101)
    @assert(array1[3] == 404)
    @assert(array2[0] == -1)
    @assert(array2[3] == -4)
}

#test
{
    let pair0 = passPair({a: 9, b: 13})
    let pair1 = passPair({a: -9, b: -13})
    let payload0 = passPayload({a0: 10'u64, a1: 20'u64, a2: 30'u64, a3: 40'u64})
    let payload1 = passPayload({a0: 1'u64, a1: 2'u64, a2: 3'u64, a3: 4'u64})

    @assert(pair0.a == 9)
    @assert(pair0.b == 13)
    @assert(pair1.a == -9)
    @assert(pair1.b == -13)
    @assert(passPairSum({a: 9, b: 13}) == 22)
    @assert(passPairSum({a: 90, b: 130}) == 220)
    @assert(passPairSum({a: -90, b: 130}) == 40)
    @assert(payload0.a0 == 10'u64)
    @assert(payload0.a3 == 40'u64)
    @assert(payload1.a0 == 1'u64)
    @assert(payload1.a3 == 4'u64)
}

#test
{
    let p0 = passPointer(null)
    let p1 = passPointer(cast(*void) 0x1234'u64)

    @assert(p0 == null)
    @assert(p1 == cast(*void) 0x1234'u64)
    @assert(passMixed(3, "mix", {a: 10, b: 11}, [8, 9], null) == 131)
    @assert(passMixed(30, "mix2", {a: 100, b: 110}, [80, 90], cast(*void) 0x4567'u64) == 330)

    const p: AbiPair = {a: 6, b: 7}
    @assert(passConstRef(p) == 13)
    @assert(passScalars(-5's8, -123's16, 77's32, 5000's64, 9'u8, 10'u16, 11'u32, 12'u64, 1.25'f32, 2.5'f64, true, 'R') == 5077)
    @assert(passBoolRunePositions(true, 3, 'Q', 4, true, 'W') == 177)
    @assert(passBoolRunePositions(false, 30, 'Q', 40, false, 'W') == 238)
    @assert(passBoolRunePositions(true, -3, 'Q', 7, false, 'W') == 173)
    @assert(passAliasEnum(1, 2, AbiEnum.A, 3) == 23)
    @assert(passAliasEnum(10, 20, AbiEnum.B, 30) == 183)
    @assert(passAliasEnum(-10, 20, AbiEnum.A, -30) == -3)
}

// @BUG native backend crashes while lowering some constant aggregate arguments in this coverage block.
/*
#test
{
    const values0: [4] s32 = [11, 22, 33, 44]
    const values1: [4] s32 = [101, 202, 303, 404]
    const values2: [4] s32 = [-1, -2, -3, -4]

    @assert(passSlice(values0, 2) == 33)
    @assert(passSlice(values1, 3) == 404)
    @assert(passSlice(values2, 0) == -1)
    @assert(passAggregatePositions(cast(*void) 0x10'u64, [5, 6], "abc", {a: 7, b: 8}, {a0: 1'u64, a1: 2'u64, a2: 3'u64, a3: 4'u64}) == 115'u64)
    @assert(passAggregatePositions(null, [50, 60], "Abc", {a: 70, b: 80}, {a0: 10'u64, a1: 20'u64, a2: 30'u64, a3: 40'u64}) == 235'u64)
    @assert(passNested({p: {a: 3, b: 4}, q: {a0: 10'u64, a1: 20'u64, a2: 30'u64, a3: 40'u64}}, 5) == 62'u64)
    @assert(passKindof({a: 1, b: 2}, {a0: 3'u64, a1: 4'u64, a2: 5'u64, a3: 6'u64}, "ok", null, [7, 8], AbiEnum.A))
    @assert(passNestedArray({p: {a: 10, b: 11}, q: {a0: 1'u64, a1: 2'u64, a2: 3'u64, a3: 4'u64}}, [{a: 20, b: 21}, {a: 30, b: 31}]) == 61)
}
*/
