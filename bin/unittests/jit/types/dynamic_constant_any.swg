#global private

alias Integer = s32

#test
{
    const value: any = 42's32
    const result     = cast #assume(s32) value
    #assert(result == 42)
    Swag.assert(cast #assume(Integer) value == 42)
}

func extractConstantWhen(enabled: bool)->s64
{
    const value: any = 42's32
    if enabled do return cast #assume(s64) value
    return 0
}

#test
{
    Swag.assert(extractConstantWhen(false) == 0)
}
