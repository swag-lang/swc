#global fileprivate

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

#test
{
    let small = #run makeSmall(2, 2)
    @assert(small.x == 4)
    @assert(small.y == 8)
}

#test
{
    let big = #run cloneBig(10)
    @assert(big.a == 11)
    @assert(big.b == 12)
    @assert(big.c == 13)
    @assert(big.d == 14)
    @assert(big.e == 15)
}

#test
{
    let (a, b, c, d, e) = makeBig(20)
    @assert(a == 21)
    @assert(b == 22)
    @assert(c == 23)
    @assert(d == 24)
    @assert(e == 25)
}

#test
{
    let first = makeBig(30)
    @assert(first.a == 31)
    @assert(first.b == 32)
    @assert(first.c == 33)
    @assert(first.d == 34)
    @assert(first.e == 35)

    let (a, ?, c, ?, e) = makeBig(40)
    @assert(a == 41)
    @assert(c == 43)
    @assert(e == 45)
}

#test
{
    let (r0, g0, b0) = makeFloat(0.5)
    @assert(r0 == 0.5)
    @assert(g0 == 0.75)
    @assert(b0 == 1.0)

    let (r1, ?, b1) = makeFloat(1.5)
    @assert(r1 == 1.5)
    @assert(b1 == 2.0)
}

#test
{
    let direct = makeFloat(2.5)
    @assert(direct.r == 2.5)
    @assert(direct.g == 2.75)
    @assert(direct.b == 3.0)

    let (r, g, b) = cloneFloat(3.5)
    @assert(r == 3.5)
    @assert(g == 3.75)
    @assert(b == 4.0)
}

