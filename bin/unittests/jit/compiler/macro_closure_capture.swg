#global private

struct JitMacroClosurePayload
{
    total: s32
}

struct JitMacroClosureState
{
    total: s32
    step:  s32
}

#[Swag.Macro]
func jitMacroInjectClosureCapture(stmt: #code)
{
    #inject(stmt)
}

#[Swag.Macro]
func jitMacroInjectCallerScopeClosureCapture(stmt: #code)
{
    #macro
    {
        #inject(#up stmt)
    }
}

#[Swag.Macro]
func jitMacroInjectCallerScopeAliasClosureCapture(seed: s32, stmt: #code(start: s32))
{
    #inject(stmt, start = seed)
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

#test
{
    jitMacroInjectClosureCapture(#code {
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

#test
{
    jitMacroInjectCallerScopeClosureCapture()
    {
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
    }
}

#test
{
    jitMacroInjectCallerScopeAliasClosureCapture(41)
    {
        func makeCounter(seed: s32)->func||()->s32
        {
            var total = seed
            return func|total|()->s32
            {
                total += 1
                return total
            }
        }

        let cb = makeCounter(start)
        @assert(cb() == 42)
        @assert(cb() == 43)
    }
}

#test
{
    jitMacroInjectCallerScopeAliasClosureCapture(41)
    {
        func makeCounter(seed: s32)->func||()->s32
        {
            var total = seed
            let step  = 2
            return func|total, step|()->s32
            {
                total += step
                return total
            }
        }

        let cb = makeCounter(start)
        @assert(cb() == 43)
        @assert(cb() == 45)
    }
}

#test
{
    jitMacroInjectCallerScopeAliasClosureCapture(41)
    {
        func makeCounter(seed: s32)->func||()->s32
        {
            var state = JitMacroClosureState{total: seed, step: 2}
            let bias  = 1
            return func|state, bias|()->s32
            {
                state.total += state.step
                return state.total + bias
            }
        }

        let cb = makeCounter(start)
        @assert(cb() == 44)
        @assert(cb() == 46)
    }
}

#test
{
    jitMacroInjectCallerScopeAliasClosureCapture(41)
    {
        func makeCounter(seed: s32)->func||()->s32
        {
            var state = JitMacroClosureState{total: seed, step: 2}
            return func|state|()->s32
            {
                state.total += state.step
                return state.total
            }
        }

        let cb = makeCounter(start)
        @assert(cb() == 43)
        @assert(cb() == 45)
    }
}
