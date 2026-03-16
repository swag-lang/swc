#global fileprivate // swc-option suite-jit

struct LambdaPair
{
    a: s32
    b: s32
}

func runExplicitLambdaArray()->bool
{
    let explicit = func(pair: LambdaPair, values: [4] s32)->[4] s32
    {
        #assert(#typeof(pair) == LambdaPair)
        #assert(#typeof(values) == [4] s32)
        return [values[0] + pair.a, values[1] + pair.b, values[2] - pair.a, values[3] - pair.b]
    }

    let result = explicit({a: 2, b: 5}, [10, 20, 30, 40])
    return result[0] == 12 and result[1] == 25 and result[2] == 28 and result[3] == 35
}

#test
{
    const ok = #run runExplicitLambdaArray()
    #assert(ok)
}
