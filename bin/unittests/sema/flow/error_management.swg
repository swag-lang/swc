#global private

struct ErrValue
{
    using base: Swag.BaseError
}

func mayFailValue()->s32 fail
{
    return 42
}

func mayFailVoid() fail {}

func plainValue()->s32
{
    return 12
}

func plainVoid() {}

func propagateValue()->s32 fail
{
    return try mayFailValue()
}

func handleValue()->s32
{
    let value: s32 = catch mayFailValue()
    return value
}

func dismissValue()->s32
{
    let value: s32 = catch mayFailValue()
    return value
}

func expectValue()->s32
{
    let value: s32 = expect mayFailValue()
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
    mayFailVoid()
}

func propagateStmt() fail
{
    try mayFailVoid()
    try
    {
        try mayFailVoid()
    }
}

func handleStmt()
{
    catch mayFailVoid()
    catch
    {
        try mayFailVoid()
    }
}
