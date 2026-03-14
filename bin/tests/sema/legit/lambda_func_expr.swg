#global fileprivate

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

struct LambdaHolder
{
    cb: LambdaAggregate
}

func invokeAggregate(cb: LambdaAggregate, payload: LambdaPayload, values: [4] s32, boxed: any)->LambdaResult
{
    return cb(payload, values, boxed)
}

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
    let result = invokeAggregate(holder.cb, {base: 7, step: 9, marks: [3'u16, 4'u16, 5'u16]}, [10, 20, 30, 40], 6)
    #assert(#typeof(result) == LambdaResult)
    #assert(#typeof(result.mirrored) == [4] s32)
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
    #assert(#typeof(result) == [4] s32)
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
    #assert(#typeof(result) == u64)
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
    #assert(#typeof(result) == s32)
}
