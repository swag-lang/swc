#global fileprivate

struct MacroClosurePayload
{
    total: s32
}

#[Swag.Macro]
func macroClosureCaptureRef(payload: MacroClosurePayload)->s32
{
    let cb = func|&payload|()->s32
    {
        payload.total += 2
        return payload.total
    }

    let first  = cb()
    let second = cb()
    return first * 10 + second
}

#test
{
    @assert(macroClosureCaptureRef(MacroClosurePayload{40}) == 464)
}
