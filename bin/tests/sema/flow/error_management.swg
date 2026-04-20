#global fileprivate

struct ErrValue
{
    using base: Swag.BaseError
}

func mayThrowValue()->s32 throw
{
    return 42
}

func mayThrowVoid() throw
{
}

func plainValue()->s32
{
    return 12
}

func plainVoid()
{
}

func propagateValue()->s32 throw
{
    return try mayThrowValue()
}

func handleValue()->s32
{
    let value: s32 = catch mayThrowValue()
    return value
}

func dismissValue()->s32
{
    let value: s32 = trycatch mayThrowValue()
    return value
}

func assumeValue()->s32
{
    let value: s32 = assume mayThrowValue()
    return value
}

func raiseValue() throw
{
    throw ErrValue{}
}

func raiseHandled()
{
    catch
    {
        throw ErrValue{}
    }
}

func directPropagateStmt() throw
{
    mayThrowVoid()
}

func propagateStmt() throw
{
    try mayThrowVoid()
    try
    {
        try mayThrowVoid()
    }
}

func handleStmt()
{
    catch mayThrowVoid()
    catch
    {
        try mayThrowVoid()
    }
}

func badDirectCall()
{
    mayThrowVoid() // swc-expected-error {{sema_err_throwable_call_requires_handler}}
}

func badTryOutside()
{
    try mayThrowVoid() // swc-expected-error {{sema_err_try_outside_throwable_context}}
}

func badThrowOutside()
{
    throw ErrValue{} // swc-expected-error {{sema_err_throw_outside_throwable_context}}
}

func badTryOperand() throw
{
    try plainVoid() // swc-expected-error {{sema_err_error_mgmt_operand_not_throwable}}
}

func badCatchOperand()
{
    catch plainVoid() // swc-expected-error {{sema_err_error_mgmt_operand_not_throwable}}
}

func badTryCatchOperand()
{
    trycatch plainVoid() // swc-expected-error {{sema_err_error_mgmt_operand_not_throwable}}
}

func badAssumeOperand()
{
    let value: s32 = assume plainValue() // swc-expected-error {{sema_err_error_mgmt_operand_not_throwable}}
    return value
}

func badTryBlock() throw
{
    try // swc-expected-error {{sema_err_error_mgmt_operand_not_throwable}}
    {
        plainVoid()
    }
}

func badCatchHandled()
{
    catch // swc-expected-error {{sema_err_error_mgmt_operand_not_throwable}}
    {
        catch mayThrowVoid()
    }
}
