#global fileprivate

struct Pair
{
    base: s32
    step: s32
}

const GlobalBonus = 2
var GlobalSeed = 40

func addOne(value: s32)->s32 => value + 1
func invokeUnary(cb: func||(s32)->s32, value: s32)->s32 => cb(value)
func relayUnary(cb: func||(s32)->s32)->func||(s32)->s32 => cb

func maybeInvoke(cb: func||()->s32 = null)->s32
{
    if cb do
        return cb()
    return -1
}

func makeParamPairClosure(pair: Pair)->func||(s32)->s32
{
    return func|pair|(value: s32)->s32
    {
        pair.base += value
        return pair.base + pair.step
    }
}

func makeParamArrayClosure(values: [3] s32)->func||()->s32
{
    return func|values|()->s32
    {
        values[1] += 1
        return values[0] + values[1] + values[2]
    }
}

#test
{
    var cb: func||(s32)->s32 = null
    @assert(cb == null)

    cb = func(value: s32)->s32 { return value + 1 }
    @assert(cb(4) == 5)

    cb = &addOne
    @assert(cb(8) == 9)

    let offset = 5
    cb = func|offset|(value: s32)->s32 { return value + offset }
    @assert(cb(3) == 8)
    @assert(cb != null)
}

#test
{
    var seed = 5
    let first: func||()->s32 = func|seed|()->s32
    {
        seed += 1
        return seed
    }

    let second: func||()->s32 = func|seed|()->s32
    {
        seed += 10
        return seed
    }

    seed = 100
    @assert(first() == 6)
    @assert(first() == 7)
    @assert(second() == 15)
    @assert(second() == 25)
    @assert(seed == 100)
}

#test
{
    var total = 0
    let inc: func||()->s32 = func|&total|()->s32
    {
        total += 1
        return total
    }

    let boost: func||()->s32 = func|&total|()->s32
    {
        total += 10
        return total
    }

    @assert(inc() == 1)
    @assert(boost() == 11)
    @assert(inc() == 12)
    @assert(total == 12)
}

#test
{
    var total = 4
    var factor = 3
    let cb: func||(s32)->s32 = func|factor, &total|(value: s32)->s32
    {
        total += value * factor
        factor += 1
        return total * 10 + factor
    }

    factor = 100
    @assert(cb(2) == 104)
    @assert(cb(1) == 145)
    @assert(total == 14)
    @assert(factor == 100)
}

#test
{
    var values: [3] s32 = [1, 2, 3]
    let cb: func||()->s32 = func|values|()->s32
    {
        return values[0] + values[1] + values[2]
    }

    values = [100, 2, 3]
    @assert(cb() == 6)
    @assert(cb() == 6)
    @assert(values[0] == 100)
}

#test
{
    var values: [3] s32 = [1, 2, 3]
    let cb: func||()->s32 = func|&values|()->s32
    {
        return values[0] + values[1] + values[2]
    }

    values = [5, 2, 3]
    @assert(cb() == 10)

    values = [20, 2, 3]
    @assert(cb() == 25)
    @assert(values[0] == 20)
}

#test
{
    let cb = makeParamPairClosure({base: 4, step: 3})
    @assert(cb(2) == 9)
    @assert(cb(1) == 10)
}

#test
{
    let cb = makeParamArrayClosure([1, 2, 3])
    @assert(cb() == 7)
    @assert(cb() == 8)
}

#test
{
    let plain = relayUnary(func(value: s32)->s32 { return value + 1 })
    @assert(plain(4) == 5)

    let fromFunction = relayUnary(&addOne)
    @assert(fromFunction(4) == 5)

    let offset = 10
    let captured = relayUnary(func|offset|(value: s32)->s32 { return value + offset })
    @assert(captured(4) == 14)
}

#test
{
    @assert(maybeInvoke() == -1)
    @assert(maybeInvoke(null) == -1)
}

#test
{
    @assert(maybeInvoke(func()->s32 { return 9 }) == 9)
}

#test
{
    @assert(invokeUnary(func(value: s32)->s32 { return value * 2 }, 6) == 12)
}

#test
{
    let factor = 3
    let cb: func||(s32)->s32 = func|factor|(value: s32)->s32 { return value * factor }
    @assert(invokeUnary(cb, 7) == 21)
}

#test
{
    let offset = 3
    let cb = func|offset|(value: s32)->s32 { return value + offset }
    @assert(cb(7) == 10)
}

#test
{
    let factor = 3
    @assert((func|factor|(value: s32)->s32 { return value * factor })(7) == 21)
}

#test
{
    let globalReader: func||()->s32 = func()->s32 { return GlobalSeed + GlobalBonus }
    @assert(globalReader() == 42)

    var text = "abc"
    let byValue: func||()->string = func|text|()->string { return text }
    let byRef: func||()->string = func|&text|()->string { return text }

    text = "zzz"
    @assert(byValue() == "abc")
    @assert(byRef() == "zzz")
}
