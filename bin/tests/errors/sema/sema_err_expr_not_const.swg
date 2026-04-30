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

func failPureCallResult()
{
    var x: s32 = 4
    const Y = pureAdd(x, 2) // swc-expected-error {{sema_err_expr_not_const}}
}

func failConstExprCallResult()
{
    var x: s32 = 4
    const Y = constMul(x, 2) // swc-expected-error {{sema_err_expr_not_const}}
}

func defaultFromPreviousParam(a: s32, b: s32 = a + 1)->s32 // swc-expected-error {{sema_err_expr_not_const}}
{
    return b
}

var RuntimeDefaultForLambda = 11
var RuntimeDefaultForFuncType = 13

func failLambdaDefaultFromRuntimeValue()
{
    let f = func(value: s32 = RuntimeDefaultForLambda)->s32 // swc-expected-error {{sema_err_expr_not_const}}
    {
        return value
    }
}

var BadFuncType: func(value: s32 = RuntimeDefaultForFuncType)->s32 = null // swc-expected-error {{sema_err_expr_not_const}}

#test { useConstCallResult() }
