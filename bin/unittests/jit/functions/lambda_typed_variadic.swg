#global private

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

alias LambdaTypedVariadic = func(LambdaPair, [2] u16, LambdaPayload...)->u64

func runTypedVariadicLambda()->u64
{
    let cb: LambdaTypedVariadic = func(pair, marks, payloads)->u64
    {
        #assert(#typeof(pair) == LambdaPair)
        #assert(#typeof(marks) == [2] u16)
        #assert(#typeof(payloads[0]) == LambdaPayload)

        var acc: u64 = cast(u64, pair.a) + cast(u64, pair.b) + cast(u64, marks[0]) + cast(u64, marks[1])
        for payload, index in payloads
        {
            acc += cast(u64, payload.base) + cast(u64, payload.marks[index])
        }

        return acc
    }

    return cb(
        {a: 3, b: 4},
        [8_u16, 9_u16],
        {base: 10, step: 1, marks: [1_u16, 2_u16, 3_u16]},
        {base: 20, step: 2, marks: [4_u16, 5_u16, 6_u16]})
}

#test
{
    const result = #run runTypedVariadicLambda()
    #assert(result == 60_u64)
}
