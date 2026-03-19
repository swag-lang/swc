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
