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
    a: s32 = undefined
    b: s32 = undefined
    c: s32 = undefined
}

func makeSmall(x, y: s32)->SmallRet
{
    var result: retval
    result.x = x * x
    result.y = y * y * y
    return result
}

func makeBig(seed: s64)->BigRet
{
    var result: retval
    result.a = seed + 1
    result.b = seed + 2
    result.c = seed + 3
    result.d = seed + 4
    result.e = seed + 5
    return result
}

func cloneBig(seed: s64)->BigRet
{
    var result: retval = makeBig(seed)
    return result
}

func makeFloat(seed: f64)->FloatRet
{
    var result: retval = undefined
    result.r = seed
    result.g = seed + 0.25
    result.b = seed + 0.5
    return result
}

func cloneFloat(seed: f64)->FloatRet
{
    var result: retval = makeFloat(seed)
    return result
}

func makeScalarDefaultRet()->s32
{
    var result: retval
    return result
}

func makeDefaultSmallRet()->DefaultSmallRet
{
    var result: retval
    result.y = 29
    return result
}

func makeDefaultNestedRet()->DefaultNestedRet
{
    var result: retval
    result.small.y = 31
    result.scale   = 70
    return result
}

func makeDefaultBigRet()->DefaultBigRet
{
    var result: retval
    result.c = 70
    return result
}

func dirtyDefaultRequiredRet()->DefaultRequiredRet
{
    var result: retval = undefined
    result.a = 101
    result.b = 202
    result.c = 303
    return result
}

func makeDefaultRequiredRet()->DefaultRequiredRet
{
    var result: retval
    result.b = 22
    return result
}

// retval with small struct via #run
#test
{
    let small = #run makeSmall(2, 2)
    Swag.assert(small.x == 4)
    Swag.assert(small.y == 8)
}

// retval with large struct via #run clone
#test
{
    let big = #run cloneBig(10)
    Swag.assert(big.a == 11)
    Swag.assert(big.b == 12)
    Swag.assert(big.c == 13)
    Swag.assert(big.d == 14)
    Swag.assert(big.e == 15)
}

// direct destructuring from an indirect retval return
#test
{
    let {a, b, c, d, e} = makeBig(20)
    Swag.assert(a == 21)
    Swag.assert(b == 22)
    Swag.assert(c == 23)
    Swag.assert(d == 24)
    Swag.assert(e == 25)
}

// repeated calls and ignored bindings must not reuse stale return storage
#test
{
    let first = makeBig(30)
    Swag.assert(first.a == 31)
    Swag.assert(first.b == 32)
    Swag.assert(first.c == 33)
    Swag.assert(first.d == 34)
    Swag.assert(first.e == 35)

    let {a, ?, c, ?, e} = makeBig(40)
    Swag.assert(a == 41)
    Swag.assert(c == 43)
    Swag.assert(e == 45)
}

// float payloads cover the original regression shape from the language reference
#test
{
    let {r0, g0, b0} = makeFloat(0.5)
    Swag.assert(r0 == 0.5)
    Swag.assert(g0 == 0.75)
    Swag.assert(b0 == 1.0)

    let {r1, ?, b1} = makeFloat(1.5)
    Swag.assert(r1 == 1.5)
    Swag.assert(b1 == 2.0)
}

// cloning through retval should still destructure correctly
#test
{
    let direct = makeFloat(2.5)
    Swag.assert(direct.r == 2.5)
    Swag.assert(direct.g == 2.75)
    Swag.assert(direct.b == 3.0)

    let {r, g, b} = cloneFloat(3.5)
    Swag.assert(r == 3.5)
    Swag.assert(g == 3.75)
    Swag.assert(b == 4.0)
}

#test
{
    Swag.assert(makeScalarDefaultRet() == 0)
}

#test
{
    let small = makeDefaultSmallRet()
    Swag.assert(small.x == 11)
    Swag.assert(small.y == 29)
}

#test
{
    let nested = makeDefaultNestedRet()
    Swag.assert(nested.small.x == 11)
    Swag.assert(nested.small.y == 31)
    Swag.assert(nested.scale == 70)
    Swag.assert(nested.enabled)
}

#test
{
    let big = makeDefaultBigRet()
    Swag.assert(big.a == 3'u64)
    Swag.assert(big.b == 5'u64)
    Swag.assert(big.c == 70'u64)
    Swag.assert(big.d == 11'u64)
    Swag.assert(big.e == 13'u64)
}

#test
{
    let dirty = dirtyDefaultRequiredRet()
    Swag.assert(dirty.a == 101)
    Swag.assert(dirty.b == 202)
    Swag.assert(dirty.c == 303)

    let clean = makeDefaultRequiredRet()
    Swag.assert(clean.a == 0)
    Swag.assert(clean.b == 22)
    Swag.assert(clean.c == 0)
}
