#global private

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
    const Y = pureAdd(x, 2)     // swc-expected-error {{sema_err_expr_not_const}}
}

func failConstExprCallResult()
{
    var x: s32 = 4
    const Y = constMul(x, 2)     // swc-expected-error {{sema_err_expr_not_const}}
}

var RuntimeBias = 2

func impureAdd(a: s32, b: s32)->s32
{
    return a + b + RuntimeBias
}

func conditionalImpureAdd(cond: bool, a: s32, b: s32)->s32
{
    if cond
    {
        return impureAdd(a, b)
    }

    return a + b
}

namespace ExprNotConstNs
{
    var RuntimeBias = 3

    func impureAdd(a: s32, b: s32)->s32
    {
        return a + b + RuntimeBias
    }

    func wrapper(a: s32, b: s32)->s32
    {
        return impureAdd(a, b)
    }

    func conditionalWrapper(cond: bool, a: s32, b: s32)->s32
    {
        if cond
        {
            return impureAdd(a, b)
        }

        return a + b
    }
}

func failImpureCallResult()
{
    const Y = impureAdd(40, 2)     // swc-expected-error {{sema_err_expr_not_const}}
}

func failConditionalImpureCallResult()
{
    const Y = conditionalImpureAdd(false, 40, 2)     // swc-expected-error {{sema_err_expr_not_const}}
}

func failNamespacedImpureCallResult()
{
    const Y = ExprNotConstNs.wrapper(40, 2)     // swc-expected-error {{sema_err_expr_not_const}}
}

func failConditionalNamespacedImpureCallResult()
{
    const Y = ExprNotConstNs.conditionalWrapper(false, 40, 2)     // swc-expected-error {{sema_err_expr_not_const}}
}

func failNamespacedDefaultArg(value: s32 = ExprNotConstNs.wrapper(40, 2))->s32     // swc-expected-error {{sema_err_expr_not_const}}
{
    return value
}

func defaultFromPreviousParam(a: s32, b: s32 = a + 1)->s32     // swc-expected-error {{sema_err_expr_not_const}}
{
    return b
}

var RuntimeDefaultForLambda = 11
var RuntimeDefaultForFuncType = 13

func failLambdaDefaultFromRuntimeValue()
{
    let f = func(value: s32 = RuntimeDefaultForLambda)->s32     // swc-expected-error {{sema_err_expr_not_const}}
    {
        return value
    }
}

var BadFuncType: func(value: s32 = RuntimeDefaultForFuncType)->s32 = null     // swc-expected-error {{sema_err_expr_not_const}}

#test { useConstCallResult() }
