#global fileprivate

struct Boundary64
{
    a, b, c, d, e, f, g, h: u64
}

struct Pair
{
    base: s32
    step: s32
}

func addOne(value: s32)->s32 => value + 1

func makeCounter(start: s32)->func||()->s32
{
    var counter = start
    return func|counter|()->s32
    {
        counter += 1
        return counter
    }
}

func runParamRefCapture(seed: s32)->s32
{
    let cb: func||()->s32 = func|&seed|()->s32
    {
        seed += 2
        return seed
    }

    let first  = cb()
    let second = cb()
    return first * 10 + second
}

func runLocalRefCapture()->s32
{
    var total = 5
    let cb: func||(s32)->s32 = func|&total|(value: s32)->s32
    {
        total += value
        return total
    }

    let first  = cb(3)
    let second = cb(4)
    @assert(total == 12)
    return first * 10 + second
}

func makeNested(base: s32)->func||()->s32
{
    let outer: func||()->func||()->s32 = func|base|()->func||()->s32
    {
        let initial = base + 1
        return func|base, initial|()->s32
        {
            initial += base
            return initial
        }
    }

    return outer()
}

#test
{
    let fromLambda: func||(s32)->s32 = func(value: s32)->s32 { return value * 3 }
    let fromFunction: func||(s32)->s32 = &addOne
    @assert(fromLambda(4) == 12)
    @assert(fromFunction(4) == 5)
}

#test
{
    let counter = makeCounter(10)
    @assert(counter() == 11)
    @assert(counter() == 12)
    @assert(counter() == 13)
}

#test
{
    @assert(runParamRefCapture(7) == 101)
}

#test
{
    @assert(runLocalRefCapture() == 92)
}

#test
{
    let pair: Pair = {base: 7, step: 4}
    let apply: func||(s32)->s32 = func|pair|(value: s32)->s32 { return pair.base + pair.step * value }
    @assert(apply(3) == 19)
}

#test
{
    let boundary: Boundary64 = {a: 1, b: 2, c: 3, d: 4, e: 5, f: 6, g: 7, h: 8}
    let sum: func||()->u64 = func|boundary|()->u64 { return boundary.a + boundary.h }
    @assert(sum() == 9'u64)
}

#test
{
    let nested = makeNested(6)
    @assert(nested() == 13)
    @assert(nested() == 19)
}
