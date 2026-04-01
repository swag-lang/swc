#global fileprivate

// Functional pipeline using closures: demonstrates capture semantics,
// higher-order functions, and closure chaining on fixed-size arrays.

const N = 8

// Basic lambda: double every element.
#test
{
    var src: [N] s32 = [1, 2, 3, 4, 5, 6, 7, 8]
    var dst: [N] s32

    let doubler: func||(s32)->s32 = func(x: s32)->s32 { return x * 2 }
    for i in @countof(src) do
        dst[i] = doubler(src[i])

    @assert(dst[0] == 2)
    @assert(dst[3] == 8)
    @assert(dst[7] == 16)
}

// Filter: keep only even numbers.
#test
{
    var src: [N] s32 = [1, 2, 3, 4, 5, 6, 7, 8]
    var dst: [N] s32
    var count: u32 = 0

    let isEven: func||(s32)->bool = func(x: s32)->bool { return x % 2 == 0 }
    for i in @countof(src)
    {
        if isEven(src[i])
        {
            dst[count] = src[i]
            count += 1
        }
    }

    @assert(count == 4)
    @assert(dst[0] == 2)
    @assert(dst[1] == 4)
    @assert(dst[2] == 6)
    @assert(dst[3] == 8)
}

// Reduce: sum using a combiner lambda.
#test
{
    var src: [N] s32 = [1, 2, 3, 4, 5, 6, 7, 8]

    let add: func||(s32, s32)->s32 = func(a: s32, b: s32)->s32 { return a + b }
    var total: s32 = 0
    for i in @countof(src) do
        total = add(total, src[i])

    @assert(total == 36)
}

// Reduce: product.
#test
{
    var src: [4] s32 = [2, 3, 4, 5]
    let mul: func||(s32, s32)->s32 = func(a: s32, b: s32)->s32 { return a * b }
    var product: s32 = 1
    for i in @countof(src) do
        product = mul(product, src[i])

    @assert(product == 120)
}

// Closure with value capture: map with offset.
#test
{
    var src: [4] s32 = [10, 20, 30, 40]
    var dst: [4] s32

    var offset = 5
    let addOffset: func||(s32)->s32 = func|offset|(x: s32)->s32 { return x + offset }
    for i in @countof(src) do
        dst[i] = addOffset(src[i])

    @assert(dst[0] == 15)
    @assert(dst[1] == 25)
    @assert(dst[2] == 35)
    @assert(dst[3] == 45)
}

// Closure with reference capture: count how many pass the filter.
#test
{
    var src: [N] s32 = [3, 7, 2, 9, 1, 8, 4, 6]
    var dst: [N] s32
    var dstCount: u32 = 0

    var callCount: s32 = 0
    let aboveFive: func||(s32)->bool = func|&callCount|(x: s32)->bool
    {
        callCount += 1
        return x > 5
    }

    for i in @countof(src)
    {
        if aboveFive(src[i])
        {
            dst[dstCount] = src[i]
            dstCount += 1
        }
    }

    @assert(dstCount == 4)
    @assert(callCount == cast(s32) N)
    @assert(dst[0] == 7)
    @assert(dst[1] == 9)
    @assert(dst[2] == 8)
    @assert(dst[3] == 6)
}

// Pipeline: square -> filter >10 -> sum.
#test
{
    var src: [6] s32 = [1, 2, 3, 4, 5, 6]
    var mapped: [6] s32
    var filtered: [6] s32
    var filteredCount: u32 = 0

    let square: func||(s32)->s32 = func(x: s32)->s32 { return x * x }
    let gtTen: func||(s32)->bool = func(x: s32)->bool { return x > 10 }
    let add: func||(s32, s32)->s32 = func(a: s32, b: s32)->s32 { return a + b }

    for i in @countof(src) do
        mapped[i] = square(src[i])

    for i in @countof(mapped)
    {
        if gtTen(mapped[i])
        {
            filtered[filteredCount] = mapped[i]
            filteredCount += 1
        }
    }

    var result: s32 = 0
    for i in filteredCount do
        result = add(result, filtered[i])

    // squares: 1, 4, 9, 16, 25, 36 -> >10: 16, 25, 36 -> sum: 77
    @assert(filteredCount == 3)
    @assert(result == 77)
}

// Multiple capture values.
#test
{
    var base = 100
    var multiplier = 3
    let compute: func||(s32)->s32 = func|base, multiplier|(x: s32)->s32
    {
        return base + x * multiplier
    }

    @assert(compute(1) == 103)
    @assert(compute(10) == 130)
    @assert(compute(0) == 100)
}

// Struct capture.
struct Pair { a, b: s32 }

#test
{
    let pair: Pair = {a: 7, b: 4}
    let apply: func||(s32)->s32 = func|pair|(value: s32)->s32 { return pair.a + pair.b * value }
    @assert(apply(3) == 19)
    @assert(apply(0) == 7)
}

// Closure returned from factory function.
func makeCounter(start: s32)->func||()->s32
{
    var counter = start
    return func|counter|()->s32
    {
        counter += 1
        return counter
    }
}

#test
{
    let counter = makeCounter(10)
    @assert(counter() == 11)
    @assert(counter() == 12)
    @assert(counter() == 13)
}

// Array of lambdas.
#test
{
    var ops: [3] func||(s32)->s32
    ops[0] = func(x: s32)->s32 { return x + 1 }
    ops[1] = func(x: s32)->s32 { return x * 2 }
    ops[2] = func(x: s32)->s32 { return x * x }

    var value: s32 = 3
    for i in @countof(ops) do
        value = ops[i](value)

    // 3 -> +1=4 -> *2=8 -> ^2=64
    @assert(value == 64)
}
