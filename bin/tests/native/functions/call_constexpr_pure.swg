#global fileprivate // 

func pureAdd(a: s32, b: s32)->s32
{
    return a + b
}

#[Swag.ConstExpr]
func constMul(a: s32, b: s32)->s32
{
    return a * b
}

func useConstCallResult()->s32
{
    const A = pureAdd(20, 22)
    const B = constMul(6, 7)
    var C = pureAdd(1, 2)
    var D = constMul(2, 3)
    var E = A + B + C + D
    return E
}

func failPureCallResult()
{
    var x: s32 = 4
}

func failConstExprCallResult()
{
    var x: s32 = 4
}

#test
{
    @assert(useConstCallResult() == 93)
}
