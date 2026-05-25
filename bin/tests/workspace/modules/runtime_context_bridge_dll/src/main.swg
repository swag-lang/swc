using RuntimeCtxBase

public const CTX_SHARED_INIT_FLAG    = 0x0008'u64
public const CTX_SHARED_PREMAIN_FLAG = 0x0010'u64
public const CTX_SHARED_DROP_FLAG    = 0x0020'u64

#init
{
    @assert((@getcontext().user1 & CTX_BASE_INIT_FLAG) != 0)
    @assert(@getcontext().allocator != null)
    @getcontext().user1 |= CTX_SHARED_INIT_FLAG
}

#premain
{
    @assert((@getcontext().user1 & CTX_BASE_PREMAIN_FLAG) != 0)
    @getcontext().user1 |= CTX_SHARED_PREMAIN_FLAG
}

#drop
{
    @assert(@getcontext().user0 == 43)
    @getcontext().user1 |= CTX_SHARED_DROP_FLAG
}

public func ctxSharedReadContext()->u64
{
    return ctxBaseReadContext()
}

public func ctxSharedContextMarker()->u64
{
    return ctxBaseContextMarker()
}

// Exercise exe -> dll calls with a wide ABI surface: scalars, aggregates, pointers and struct returns.
public alias CtxAbiAlias = s32

public enum CtxAbiEnum: u16
{
    A = 17
    B = 123
}

public struct CtxAbiPair
{
    a: s32
    b: s32
}

public struct CtxAbiPayload
{
    a0: u64
    a1: u64
    a2: u64
    a3: u64
}

public struct CtxAbiOffsets
{
    a: u8
    b: u16
    c: u32
    d: u64
}

public struct CtxAbiNested
{
    p: CtxAbiPair
    q: CtxAbiPayload
}

public struct CtxAbiFloatPack
{
    r: f64
    g: f64
    b: f64
}

public struct CtxAbiCalculator
{
    base: s32
}

public struct CtxClosureByteSet
{
    values: [4] u8
    count:  u32
}

public struct CtxSelfBufferSet
{
    buffer:  [*] u8
    count:   u32
    storage: [4] u8
}

public impl CtxClosureByteSet
{
    #[Swag.NoInline]
    mtd const contains(value: u8)->bool
    {
        return ctxSharedContains(values, count, value)
    }
}

public impl CtxSelfBufferSet
{
    mtd opPostMove()
    {
        if buffer do
            buffer = cast([*] u8) &storage[0]
    }

    mtd opPostCopy()
    {
        if buffer do
            buffer = cast([*] u8) &storage[0]
    }

    #[Swag.NoInline]
    mtd const toSlice()->const [..] u8
    {
        @assert(buffer == cast([*] u8) &storage[0])
        return @mkslice(buffer, count)
    }

    #[Swag.NoInline]
    mtd const contains(value: u8)->bool
    {
        @assert(buffer == cast([*] u8) &storage[0])
        return ctxSharedContains(.toSlice(), count, value)
    }

    #[Swag.NoInline]
    mtd const containsViaGeneric(value: u8)->bool
    {
        @assert(buffer == cast([*] u8) &storage[0])
        return ctxSharedContainsGeneric(.toSlice(), count, value)
    }
}

#[Swag.NoInline]
public func ctxSharedMakeSelfBufferSet(a: u8, b: u8, c: u8, d: u8, count: u32)->CtxSelfBufferSet
{
    var result: retval = undefined
    result.storage = [a, b, c, d]
    result.buffer  = cast([*] u8) &result.storage[0]
    result.count   = count
    return result
}

#[Swag.NoInline]
public func ctxSharedContains(values: const [..] u8, count: u32, value: u8)->bool
{
    for i in count
    {
        if values[i] == value do
            return true
    }

    return false
}

#[Swag.NoInline]
public func(T) ctxSharedContainsGeneric(values: const [..] T, count: u32, value: T)->bool
{
    for i in count
    {
        if values[i] == value do
            return true
    }

    return false
}

public impl CtxClosureByteSet
{
    #[Swag.NoInline]
    mtd const containsViaGeneric(value: u8)->bool
    {
        return ctxSharedContainsGeneric(values, count, value)
    }
}

public func ctxSharedPassString(text: string)->string
{
    return text
}

#[Swag.NoInline]
public func ctxSharedInvokeUnary(value: u8, cb: func||(u8)->bool)->bool
{
    return cb(value)
}

#[Swag.NoInline]
public func(T) ctxSharedInvokeGeneric(value: T, cb: func||(T)->bool)->bool
{
    return cb(value)
}

#[Swag.NoInline]
public func(T) ctxSharedAllOf(values: const [..] T, cb: func||(T)->bool)->bool
{
    foreach v in values
    {
        if !cb(v) do
            return false
    }

    return true
}

public func ctxSharedPassStringAt(text: string, idx: s32)->u8
{
    return text[idx]
}

public func ctxSharedPassArray(values: [4] s32)->[4] s32
{
    return values
}

public func ctxSharedPassPair(value: CtxAbiPair)->CtxAbiPair
{
    return value
}

public func ctxSharedPassPairSum(value: CtxAbiPair)->s32
{
    return value.a + value.b
}

public func ctxSharedPassPayload(value: CtxAbiPayload)->CtxAbiPayload
{
    return value
}

public func ctxSharedPassOffsets(value: CtxAbiOffsets)->u64
{
    return cast(u64) value.a + cast(u64) value.b + cast(u64) value.c + value.d
}

public func ctxSharedPassPointer(value: *void)->*void
{
    return value
}

public func ctxSharedPassMixed(a: s32, b: string, c: CtxAbiPair, d: [2] s32, e: *void)->s32
{
    return a + cast(s32) b[0] + c.a + d[1] + cast(s32) (e != null)
}

public func ctxSharedPassConstRef(value: const &CtxAbiPair)->s32
{
    return value.a + value.b
}

public func ctxSharedPassScalars(a0: s8, a1: s16, a2: s32, a3: s64, a4: u8, a5: u16, a6: u32, a7: u64, a8: f32, a9: f64, a10: bool, a11: rune)->s32
{
    return cast(s32) a0 + cast(s32) a1 + a2 + cast(s32) a3 + cast(s32) a4 + cast(s32) a5 + cast(s32) a6 + cast(s32) a7 + cast(s32) a8 + cast(s32) a9 + cast(s32) a10 + cast(s32) a11
}

public func ctxSharedPassBoolRunePositions(a: bool, b: s32, c: rune, d: s32, e: bool, f: rune)->s32
{
    return cast(s32) a + b + cast(s32) c + d + cast(s32) e + cast(s32) f
}

public func ctxSharedPassAliasEnum(a: s32, b: CtxAbiAlias, c: CtxAbiEnum, d: s32)->s32
{
    return a + b + cast(s32) cast(u16) c + d
}

public func ctxSharedPassSlice(values: const [..] s32, idx: s32)->s32
{
    return values[idx]
}

public func ctxSharedPassAggregatePositions(a: *void, b: [2] s32, c: string, d: CtxAbiPair, e: CtxAbiPayload)->u64
{
    return cast(u64) b[1] + cast(u64) d.a + e.a3 + cast(u64) c[0] + cast(u64) (a != null)
}

public func ctxSharedPassNested(value: CtxAbiNested, extra: s32)->u64
{
    return cast(u64) value.p.a + cast(u64) value.p.b + value.q.a0 + value.q.a3 + cast(u64) extra
}

public func ctxSharedPassKindof(value: CtxAbiPair, payload: CtxAbiPayload, text: string, p: *void, values: [2] s32, e: CtxAbiEnum)->bool
{
    return #typeof(value) == CtxAbiPair and #typeof(payload) == CtxAbiPayload and #typeof(text) == string and #typeof(p) == *void and #typeof(values[1]) == s32 and #typeof(e) == CtxAbiEnum
}

public func ctxSharedPassNestedArray(value: CtxAbiNested, array0: [2] CtxAbiPair)->s32
{
    return value.p.a + array0[0].b + array0[1].a
}

public func ctxSharedWritePair(dst: *CtxAbiPair, a: s32, b: s32)
{
    @assert(dst != null)
    dst.a = a
    dst.b = b
}

public func ctxSharedWritePayload(dst: *CtxAbiPayload, seed: u64)
{
    @assert(dst != null)
    dst.a0 = seed + 1
    dst.a1 = seed + 2
    dst.a2 = seed + 3
    dst.a3 = seed + 4
}

public func ctxSharedMakePair(a: s32, b: s32)->CtxAbiPair
{
    return {a: a, b: b}
}

public func ctxSharedMakePayload(seed: u64)->CtxAbiPayload
{
    var result: retval = undefined
    result.a0 = seed + 1
    result.a1 = seed + 2
    result.a2 = seed + 3
    result.a3 = seed + 4
    return result
}

public func ctxSharedMakeOffsets(a: u8, b: u16, c: u32, d: u64)->CtxAbiOffsets
{
    return {a: a, b: b, c: c, d: d}
}

public func ctxSharedMakeNested(seed: s32)->CtxAbiNested
{
    var result: retval = undefined
    result.p.a  = seed
    result.p.b  = seed + 1
    result.q.a0 = cast(u64) seed + 10
    result.q.a1 = cast(u64) seed + 20
    result.q.a2 = cast(u64) seed + 30
    result.q.a3 = cast(u64) seed + 40
    return result
}

public func ctxSharedMakeFloatPack(seed: f64)->CtxAbiFloatPack
{
    var result: retval = undefined
    result.r = seed
    result.g = seed + 0.25
    result.b = seed + 0.5
    return result
}

public func ctxSharedClonePayload(value: CtxAbiPayload)->CtxAbiPayload
{
    var result: retval = value
    return result
}

public func ctxSharedCloneFloatPack(value: CtxAbiFloatPack)->CtxAbiFloatPack
{
    var result: retval = value
    return result
}

public func ctxSharedScale(value: s32)->s32
{
    return value * 4
}

public func ctxSharedScale(value: f32)->f32
{
    return value * 4
}

public impl CtxAbiCalculator
{
    func make(base: s32)->CtxAbiCalculator
    {
        return {base}
    }

    func resolve(value: s32)->s32
    {
        return value + 100
    }

    mtd resolve(value: s32)->s32
    {
        return .base + value + 1000
    }

    mtd const add(value: s32)->s32
    {
        return .base + value
    }

    mtd const add(value: f32)->f32
    {
        return cast(f32) .base + value
    }

    mtd const sub(value: s32)->s32
    {
        return .base - value
    }

    mtd const makePair(delta: s32)->CtxAbiPair
    {
        return {a: .base + delta, b: .base - delta}
    }

    mtd const makePayload(seed: u64)->CtxAbiPayload
    {
        return ctxSharedMakePayload(seed + cast(u64) .base)
    }
}
