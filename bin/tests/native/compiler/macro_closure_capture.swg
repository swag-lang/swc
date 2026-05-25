#global fileprivate

struct MacroClosurePayload
{
    total: s32
}

#[Swag.Macro]
func macroInjectClosureCapture(stmt: #code void)
{
    #inject(stmt)
}

func macroClosureCaptureRunTwice(cb: func||()->s32)->s32
{
    let first  = cb()
    let second = cb()
    return first * 10 + second
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

#test
{
    var payload = MacroClosurePayload{40}
    macroInjectClosureCapture(#code {
        @assert(macroClosureCaptureRunTwice(func|&payload|()->s32 {
            payload.total += 2
            return payload.total
        }) == 464)
    })
}
