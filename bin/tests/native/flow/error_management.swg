#global fileprivate

func mayThrowValue()->s32 throw
{
    return 42
}

func mayThrowVoid() throw
{
}

func propagateValue()->s32 throw
{
    return try mayThrowValue()
}

func handleValue()->s32
{
    return catch mayThrowValue()
}

func dismissValue()->s32
{
    return trycatch mayThrowValue()
}

func assumeValue()->s32
{
    return assume mayThrowValue()
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
