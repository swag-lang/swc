#global fileprivate

#[Swag.Macro]
func macroClosureCaptureValue(value: s32)->s32
{
    let cb = func|value|()->s32
    {
        return value + 1
    }

    return cb()
}

#test
{
    @assert(macroClosureCaptureValue(20 + 21) == 42)
}
