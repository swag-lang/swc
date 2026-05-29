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

#test
{
    macroInjectClosureCapture(#code {
        func makeCounter(start: s32)->func||()->s32
        {
            var total = start
            return func|total|()->s32
            {
                total += 1
                return total
            }
        }

        let cb = makeCounter(41)
        @assert(cb() == 42)
        @assert(cb() == 43)
    })
}
