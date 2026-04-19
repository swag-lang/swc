#global fileprivate // 

struct LambdaPair
{
    a: s32
    b: s32
}

struct LambdaPayload
{
    base:  s32
    step:  s32
    marks: [3] u16
}

struct LambdaResult
{
    total:    s64
    mirrored: [4] s32
    pair:     LambdaPair
}

alias LambdaAggregate = func(LambdaPayload, [4] s32, any)->LambdaResult
alias LambdaTypedVariadic = func(LambdaPair, [2] u16, LambdaPayload...)->u64
alias LambdaUntypedVariadic = func(bool, ...)->s32
alias LambdaUnary = func(s32)->s32
alias LambdaBinaryPredicate = func(s32, s32)->bool
alias LambdaDefaultUnary = func(value: s32 = 11)->s32
alias LambdaDefaultBool = func(flag: bool = true)->bool

enum LambdaDefaultCategory
{
    Default
    Effects
}

alias LambdaDefaultCategoryFn = func(category = LambdaDefaultCategory.Effects)->LambdaDefaultCategory

struct LambdaHolder
{
    cb: LambdaAggregate
}

struct LambdaRuntimeHolder
{
    unary:     LambdaUnary
    predicate: LambdaBinaryPredicate
    defaulted: LambdaDefaultUnary
}

struct LambdaArrayHolder
{
    callbacks: [2] LambdaUnary
}

func invokeAggregate(cb: LambdaAggregate, payload: LambdaPayload, values: [4] s32, boxed: any)->LambdaResult
{
    return cb(payload, values, boxed)
}

func invokeUnary(cb: LambdaUnary, value: s32)->s32
{
    return cb(value)
}

func invokeBinary(cb: LambdaBinaryPredicate, left: s32, right: s32)->bool
{
    return cb(left, right)
}

func invokeDefaulted(cb: LambdaDefaultUnary)->s32
{
    return cb() * 100 + cb(4) * 10 + cb(value: 2)
}

func relayUnary(cb: LambdaUnary)->LambdaUnary
{
    return cb
}

func makeDouble()->LambdaUnary
{
    return func(value) => value + value
}

func makeDefaulted()->LambdaDefaultUnary
{
    return func(value) => value * 3
}

func makeRuntimeHolder()->LambdaRuntimeHolder
{
    return {
        unary: func(value) => value + 4,
        predicate: func(left, right) => left < right,
        defaulted: func(value) => value + 2,
    }
}

func makeArrayHolder()->LambdaArrayHolder
{
    return {
        callbacks: [
            func(value) => value + 1,
            func(value) => value * 2,
        ],
    }
}

func plusTen(value: s32)->s32 => value + 10
func squareValue(value: s32)->s32 => value * value

#test
{
    let cb: LambdaAggregate = func(payload, values, boxed)
    {
        #assert(#typeof(payload) == LambdaPayload)
        #assert(#typeof(values) == [4] s32)
        #assert(#typeof(boxed) == any)

        return {
            total: cast(s64) payload.base + cast(s64) values[0] + cast(s64) values[3] + cast(s64) cast(s32) boxed,
            mirrored: [values[3], values[2], values[1], values[0]],
            pair: {a: payload.step + cast(s32) payload.marks[1], b: cast(s32) payload.marks[2]},
        }
    }

    var holder: LambdaHolder = {cb: cb}
    var callbacks: [2] LambdaAggregate
    callbacks[0] = holder.cb
    callbacks[1] = cb

    let direct = cb({base: 7, step: 9, marks: [3'u16, 4'u16, 5'u16]}, [10, 20, 30, 40], 6)
    let held = holder.cb({base: 7, step: 9, marks: [3'u16, 4'u16, 5'u16]}, [10, 20, 30, 40], 6)
    let res0 = callbacks[0]({base: 7, step: 9, marks: [3'u16, 4'u16, 5'u16]}, [10, 20, 30, 40], 6)
    let viaArray = callbacks[1]({base: 7, step: 9, marks: [3'u16, 4'u16, 5'u16]}, [10, 20, 30, 40], 6)
    let viaHeldInvoke = invokeAggregate(holder.cb, {base: 7, step: 9, marks: [3'u16, 4'u16, 5'u16]}, [10, 20, 30, 40], 6)
    let viaArray0Invoke = invokeAggregate(callbacks[0], {base: 7, step: 9, marks: [3'u16, 4'u16, 5'u16]}, [10, 20, 30, 40], 6)
    let res1 = invokeAggregate(callbacks[1], {base: 1, step: 2, marks: [8'u16, 9'u16, 10'u16]}, [5, 6, 7, 8], 4)

    @assert(res0.total == 63)
    @assert(res0.mirrored[0] == 40)
    @assert(res0.mirrored[3] == 10)
    @assert(res0.pair.a == 13)
    @assert(res0.pair.b == 5)

    @assert(res1.total == 18)
    @assert(res1.mirrored[0] == 8)
    @assert(res1.pair.a == 11)
    @assert(res1.pair.b == 10)
}

#test
{
    let explicit = func(pair: LambdaPair, values: [4] s32)->[4] s32
    {
        #assert(#typeof(pair) == LambdaPair)
        #assert(#typeof(values) == [4] s32)
        return [values[0] + pair.a, values[1] + pair.b, values[2] - pair.a, values[3] - pair.b]
    }

    let result = explicit({a: 2, b: 5}, [10, 20, 30, 40])
    @assert(result[0] == 12)
    @assert(result[1] == 25)
    @assert(result[2] == 28)
    @assert(result[3] == 35)
}

#test
{
    let cb: LambdaTypedVariadic = func(pair, marks, payloads)->u64
    {
        #assert(#typeof(pair) == LambdaPair)
        #assert(#typeof(marks) == [2] u16)
        #assert(#typeof(payloads[0]) == LambdaPayload)

        var acc: u64 = cast(u64) pair.a + cast(u64) pair.b + cast(u64) marks[0] + cast(u64) marks[1]
        foreach payload, index in payloads
        {
            acc += cast(u64) payload.base + cast(u64) payload.marks[index]
        }

        return acc
    }

    let result = cb(
        {a: 3, b: 4},
        [8'u16, 9'u16],
        {base: 10, step: 1, marks: [1'u16, 2'u16, 3'u16]},
        {base: 20, step: 2, marks: [4'u16, 5'u16, 6'u16]})
    @assert(result == 60'u64)
}

#test
{
    let cb: LambdaUntypedVariadic = func(flag, values)->s32
    {
        #assert(#typeof(flag) == bool)
        #assert(#typeof(values[0]) == any)
        #assert(#typeof(values[1]) == any)
        #assert(#typeof(values[2]) == any)

        let text = cast(string) values[2]
        return cast(s32) values[0] + cast(s32) values[1] + cast(s32) text[1] + cast(s32) flag
    }

    let result = cb(true, 4, 7, "AZ")
    @assert(result == 102)
}

#test
{
    var cb: LambdaUnary
    @assert(cb == null)

    cb = &plusTen
    @assert(cb(5) == 15)

    cb = func(value) => value - 3
    @assert(cb(9) == 6)
    @assert(cb != null)
}

#test
{
    @assert(invokeUnary(func(value) => value * value, 4) == 16)
    @assert(invokeUnary(value: 5, cb: func(value) { return value + value }) == 10)
    @assert(invokeUnary(func(value: s32)->s32 { return value - 1 }, 8) == 7)
    @assert(invokeBinary(func(left, right) => left <= right, 4, 4))
    @assert(!invokeBinary(func(left: s32, right: s32)->bool { return left > right }, 4, 9))
}

#test
{
    var predicate: LambdaBinaryPredicate

    predicate = func(left, right) => left == right
    @assert(predicate(10, 10))
    @assert(!predicate(10, 11))

    predicate = func(left, right)
    {
        return left != right
    }

    @assert(predicate(20, 120))
    @assert(!predicate(20, 20))
}

#test
{
    let relayed = relayUnary(func(value) => value * 3)

    @assert(relayed(6) == 18)
}

#test
{
    let local = func(flag = true) => flag

    @assert(local())
    @assert(!local(false))
}

#test
{
    var bound: func(flag: bool = true)->bool
    bound = func(flag)
    {
        return flag
    }

    @assert(bound())
    @assert(!bound(false))
    @assert(bound(true))
    @assert(!bound(flag: false))
}

#test
{
    let defaulted: LambdaDefaultCategoryFn = func(category) => category

    @assert(defaulted() == LambdaDefaultCategory.Effects)
    @assert(defaulted(LambdaDefaultCategory.Default) == LambdaDefaultCategory.Default)
    @assert(defaulted(category: LambdaDefaultCategory.Default) == LambdaDefaultCategory.Default)
}

#test
{
    let increment: LambdaDefaultUnary = func(value) => value + 1
    let invert: LambdaDefaultBool = func(flag) => !flag

    @assert(increment() == 12)
    @assert(increment(8) == 9)
    @assert(increment(value: 3) == 4)
    @assert(invokeDefaulted(increment) == 1253)

    @assert(!invert())
    @assert(invert(false))
    @assert(!invert(flag: true))
}

#test
{
    let cb: LambdaDefaultUnary = func(value) => value * 2
    @assert(cb() == 22)
    @assert(cb(6) == 12)
    @assert(cb(value: 3) == 6)
    @assert(invokeDefaulted(cb) == 2284)
}

#test
{
    let seedDefaulted: LambdaDefaultUnary = func(value) => value + 1
    var holder: LambdaRuntimeHolder = {
        unary: func(value) => value + 4,
        predicate: func(left, right) => left == right,
        defaulted: func(value) => value + 5,
    }

    let explicit = LambdaRuntimeHolder{
        unary: func(value) => value - 2,
        predicate: func(left, right) => left < right,
        defaulted: seedDefaulted,
    }

    holder.unary = func(value) => value * 5
    holder.predicate = func(left, right) => left >= right
    holder.defaulted = func(value) => value - 1

    @assert(holder.unary(4) == 20)
    @assert(holder.predicate(9, 9))
    @assert(!holder.predicate(2, 7))
    @assert(holder.defaulted() == 10)
    @assert(holder.defaulted(8) == 7)
    @assert(holder.defaulted(value: 6) == 5)
    @assert(explicit.unary(7) == 5)
    @assert(explicit.predicate(3, 8))
    @assert(!explicit.predicate(8, 3))
    @assert(explicit.defaulted() == 12)
}

#test
{
    var callbacks: [3] LambdaUnary = [
        func(value) => value + 1,
        func(value) => value * 2,
        func(value) => value - 3,
    ]
    callbacks[1] = func(value)
    {
        return value * 4
    }
    callbacks[2] = &squareValue

    @assert(callbacks[0](4) == 5)
    @assert(callbacks[1](4) == 16)
    @assert(callbacks[2](5) == 25)
}

#test
{
    let direct = invokeDefaulted(func(value) => value + 2)
    @assert(direct == 1364)
}

#test
{
    let doubled = makeDouble()
    let defaulted = makeDefaulted()

    @assert(doubled(7) == 14)
    @assert(defaulted() == 33)
    @assert(defaulted(5) == 15)
}

#test
{
    let holder = makeRuntimeHolder()
    let nested = makeArrayHolder()

    @assert(holder.unary(3) == 7)
    @assert(holder.predicate(2, 5))
    @assert(!holder.predicate(8, 1))
    @assert(holder.defaulted() == 13)
    @assert(holder.defaulted(6) == 8)

    @assert(nested.callbacks[0](5) == 6)
    @assert(nested.callbacks[1](5) == 10)
}
