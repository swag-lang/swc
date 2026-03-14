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

func invokeAggregate(cb: LambdaAggregate, payload: LambdaPayload, values: [4] s32, boxed: any)->LambdaResult
{
    return cb(payload, values, boxed)
}

func runAggregateLambda()->bool
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

    let res0 = invokeAggregate(cb, {base: 7, step: 9, marks: [3'u16, 4'u16, 5'u16]}, [10, 20, 30, 40], 6)
    let res1 = invokeAggregate(cb, {base: 1, step: 2, marks: [8'u16, 9'u16, 10'u16]}, [5, 6, 7, 8], 4)

    return res0.total == 63 and
           res0.mirrored[0] == 40 and
           res0.mirrored[3] == 10 and
           res0.pair.a == 13 and
           res0.pair.b == 5 and
           res1.total == 18 and
           res1.mirrored[0] == 8 and
           res1.pair.a == 11 and
           res1.pair.b == 10
}

#test
{
    const ok = #run runAggregateLambda()
    #assert(ok)
}
