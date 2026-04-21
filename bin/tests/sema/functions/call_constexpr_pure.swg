#global fileprivate

func pureAdd(a: s32, b: s32)->s32
{
    return a + b
}

#[Swag.ConstExpr]
func constMul(a: s32, b: s32)->s32
{
    return a * b
}

func useConstCallResult()
{
    const A = pureAdd(20, 22)
    const B = constMul(6, 7)
    var C = pureAdd(1, 2)
    var D = constMul(2, 3)
    var E = A + B + C + D
}

#test { useConstCallResult() }
