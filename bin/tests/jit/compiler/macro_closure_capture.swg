#global fileprivate

struct JitMacroClosurePayload
{
    total: s32
}

#[Swag.Macro]
func jitMacroInjectClosureCapture(stmt: #code void)
{
    #inject(stmt)
}

func jitMacroClosureCaptureRunTwice(cb: func||()->s32)->s32
{
    let first  = cb()
    let second = cb()
    return first * 10 + second
}

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

#test
{
    var payload = JitMacroClosurePayload{40}
    jitMacroInjectClosureCapture(#code {
        @assert(jitMacroClosureCaptureRunTwice(func|&payload|()->s32 {
            payload.total += 2
            return payload.total
        }) == 464)
    })
}
