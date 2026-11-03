#global private

struct SmallRet
{
    x: s32
    y: s32
}

struct BigRet
{
    a: s64
    b: s64
    c: s64
    d: s64
    e: s64
}

struct FloatRet
{
    r: f64
    g: f64
    b: f64
}

struct DefaultSmallRet
{
    x: s32 = 11
    y: s32 = 23
}

struct DefaultNestedRet
{
    small:   DefaultSmallRet
    scale:   s32  = 7
    enabled: bool = true
}

struct DefaultBigRet
{
    a: u64 = 3
    b: u64 = 5
    c: u64 = 7
    d: u64 = 11
    e: u64 = 13
}

struct DefaultRequiredRet
{
    a: s32
    b: s32
    c: s32
}

func makeSmall(x, y: s32)->SmallRet
{
    var result: #returntype
    result.x = x * x
    result.y = y * y * y
    return result
}

func makeBig(seed: s64)->BigRet
{
    var result: #returntype
    result.a = seed + 1
    result.b = seed + 2
    result.c = seed + 3
    result.d = seed + 4
    result.e = seed + 5
    return result
}

func cloneBig(seed: s64)->BigRet
{
    var result: #returntype = makeBig(seed)
    return result
}

func makeFloat(seed: f64)->FloatRet
{
    var result: #returntype
    result.r = seed
    result.g = seed + 0.25
    result.b = seed + 0.5
    return result
}

func cloneFloat(seed: f64)->FloatRet
{
    var result: #returntype = makeFloat(seed)
    return result
}

func makeScalarDefaultRet()->s32
{
    var result: #returntype
    return result
}

func makeDefaultSmallRet()->DefaultSmallRet
{
    var result: #returntype
    result.y = 29
    return result
}

func makeDefaultNestedRet()->DefaultNestedRet
{
    var result: #returntype
    result.small.y = 31
    result.scale   = 70
    return result
}

func makeDefaultBigRet()->DefaultBigRet
{
    var result: #returntype
    result.c = 70
    return result
}

func dirtyDefaultRequiredRet()->DefaultRequiredRet
{
    var result: #returntype
    result.a = 101
    result.b = 202
    result.c = 303
    return result
}

func makeDefaultRequiredRet()->DefaultRequiredRet
{
    var result: #returntype
    result.b = 22
    return result
}

// #returntype with small struct via #run
#test
{
    let small = #run makeSmall(2, 2)
    Swag.require(small.x == 4)
    Swag.require(small.y == 8)
}

// #returntype with large struct via #run clone
#test
{
    let big = #run cloneBig(10)
    Swag.require(big.a == 11)
    Swag.require(big.b == 12)
    Swag.require(big.c == 13)
    Swag.require(big.d == 14)
    Swag.require(big.e == 15)
}

// direct destructuring from an indirect return
#test
{
    let {a, b, c, d, e} = makeBig(20)
    Swag.require(a == 21)
    Swag.require(b == 22)
    Swag.require(c == 23)
    Swag.require(d == 24)
    Swag.require(e == 25)
}

// repeated calls and ignored bindings must not reuse stale return storage
#test
{
    let first = makeBig(30)
    Swag.require(first.a == 31)
    Swag.require(first.b == 32)
    Swag.require(first.c == 33)
    Swag.require(first.d == 34)
    Swag.require(first.e == 35)

    let {a, b: _, c, d: _, e} = makeBig(40)
    Swag.require(a == 41)
    Swag.require(c == 43)
    Swag.require(e == 45)
}

// float payloads cover the original regression shape from the language reference
#test
{
    let {r: r0, g: g0, b: b0} = makeFloat(0.5)
    Swag.require(r0 == 0.5)
    Swag.require(g0 == 0.75)
    Swag.require(b0 == 1.0)

    let {r: r1, g: _, b: b1} = makeFloat(1.5)
    Swag.require(r1 == 1.5)
    Swag.require(b1 == 2.0)
}

// cloning through #returntype should still destructure correctly
#test
{
    let direct = makeFloat(2.5)
    Swag.require(direct.r == 2.5)
    Swag.require(direct.g == 2.75)
    Swag.require(direct.b == 3.0)

    let {r, g, b} = cloneFloat(3.5)
    Swag.require(r == 3.5)
    Swag.require(g == 3.75)
    Swag.require(b == 4.0)
}

#test
{
    Swag.require(makeScalarDefaultRet() == 0)
}

#test
{
    let small = makeDefaultSmallRet()
    Swag.require(small.x == 11)
    Swag.require(small.y == 29)
}

#test
{
    let nested = makeDefaultNestedRet()
    Swag.require(nested.small.x == 11)
    Swag.require(nested.small.y == 31)
    Swag.require(nested.scale == 70)
    Swag.require(nested.enabled)
}

#test
{
    let big = makeDefaultBigRet()
    Swag.require(big.a == 3'u64)
    Swag.require(big.b == 5'u64)
    Swag.require(big.c == 70'u64)
    Swag.require(big.d == 11'u64)
    Swag.require(big.e == 13'u64)
}

#test
{
    let dirty = dirtyDefaultRequiredRet()
    Swag.require(dirty.a == 101)
    Swag.require(dirty.b == 202)
    Swag.require(dirty.c == 303)

    let clean = makeDefaultRequiredRet()
    Swag.require(clean.a == 0)
    Swag.require(clean.b == 22)
    Swag.require(clean.c == 0)
}
