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
