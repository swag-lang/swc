#global fileprivate

#[Swag.ConstExpr]
func constMul(a: s32, b: s32)->s32
{
    return a * b
}

#[Swag.ConstExpr]
func constMix(a: s32, b: s32, c: s32)->s32
{
    return a * b + c
}

func pureAdd(a: s32, b: s32)->s32
{
    return a + b
}

func wrapConstexprCall()->s32
{
    const A = constMul(6, 7)
    const B = constMix(4, 10, 2)
    return A + B
}

func wrapPureConstexprNoRun()->s32
{
    const A = pureAdd(20, 22)
    const B = constMul(3, 14)
    return A + B
}

func wrapNestedNoRun()->s32
{
    const A = constMul(constMul(2, 3), 7)
    const B = pureAdd(pureAdd(10, 11), 21)
    return A + B
}

func wrapRuntimeArgNoRun(x: s32)->s32
{
    var Y = constMul(x, 2)
    return Y
}

#test
{
    const V = constMul(6, 7)
    #assert(V == 42)
}

#test
{
    const V = #run constMix(4, 10, 2)
    #assert(V == 42)
}

#test
{
    const V = #run wrapConstexprCall()
    #assert(V == 84)
}

#test
{
    const V = #run wrapPureConstexprNoRun()
    #assert(V == 84)
}

#test
{
    const V = #run wrapNestedNoRun()
    #assert(V == 84)
}

#test
{
    const V = #run wrapRuntimeArgNoRun(21)
    #assert(V == 42)
}
