#global private

alias Integer = s32

#test
{
    const value: any = 42's32
    const result     = assume cast(s32, value)
    #assert(result == 42)
    Swag.require(assume cast(Integer, value) == 42)
}

func extractConstantWhen(enabled: bool)->s64
{
    const value: any = 42's32
    if enabled do return assume cast(s64, value)
    return 0
}

#test
{
    Swag.require(extractConstantWhen(false) == 0)
}
