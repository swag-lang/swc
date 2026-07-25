#global private

struct ErrValue
{
    using base: Swag.BaseError
}

func mayThrowValue()->s32 fail
{
    return 42
}

func mayThrowVoid() fail {}

func plainValue()->s32
{
    return 12
}

func plainVoid() {}

func propagateValue()->s32 fail
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
    let value: s32 = mayThrowValue() orfail 0
    return value
}

func assumeValue()->s32
{
    let value: s32 = expect mayThrowValue()
    return value
}

func raiseValue() fail
{
    fail ErrValue{}
}

func raiseHandled()
{
    catch
    {
        fail ErrValue{}
    }
}

func directPropagateStmt() fail
{
    mayThrowVoid()
}

func propagateStmt() fail
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
