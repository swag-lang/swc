#global fileprivate

#[Swag.Macro]
func(T) localGenericSignature(value: T)->T
{
    func typedIdentity(input: T)->T
    {
        return input
    }

    return typedIdentity(value)
}

#[Swag.Macro]
func localMacroRelay(seed: s32)->s32
{
    func emit(value: s32)->s32
    {
        #macro
        {
            return #up value * 2
        }
    }

    return emit(seed)
}

#[Swag.Macro]
func aliasBounce(value: s32)->s32
{
    #macro
    {
        let #alias0 = #up value
        #macro
        {
            return #up buffer + 1
        }
    }
}

#[Swag.Macro]
func localNestedUpShadow(seed: s32)->s32
{
    func pick(seed: s32, buffer: s32)->s32
    {
        return aliasBounce(|buffer| #up seed)
    }

    return pick(seed, 1000)
}

func forcedLocalMacroRelay(seed: s32)->s32
{
    #[Swag.Macro]
    func emit(value: s32)->s32
    {
        #macro
        {
            return #up value * 3
        }
    }

    return emit(seed)
}

#test
{
    @assert(localGenericSignature(41) == 41)
}

#test
{
    @assert(localMacroRelay(21) == 42)
}

#test
{
    @assert(localNestedUpShadow(41) == 42)
}

#test
{
    @assert(forcedLocalMacroRelay(14) == 42)
}

// Tests for #macro { #inject } inside a for loop inside a local function.
// Verifies the codegen fix for inline-label placement in locally-compiled functions.
// This is the exact pattern used by Jobs.parallelVisit / Jobs.parallelFor.
#[Swag.Macro]
func localForMacroInject(count: s32, contextData: *void = null, stmt: #code void)
{
    func doWork(n: s32, ctxData: *void)
    {
        for n
        {
            #macro
            {
                let #alias0 = #up ctxData
                let #alias1 = #up ctxData
                #inject(#up stmt)
            }
        }
    }

    doWork(count, contextData)
}

#test
{
    // Verify that #macro { #inject } inside a for loop in a local function runs correctly
    var runs = 0
    localForMacroInject(3, &runs)
    {
        discard @atomadd(cast(*s32) #alias0, 1)
    }
    @assert(runs == 3)
}

// Verifies two-level nested macro injection (outer macro → local-function for loop)
// correctly handles 'return' inside the injected code block via doneLabel placement.
#[Swag.Macro]
func parallelVisitLike(ctxData: *void = null, stmt: #code void)
{
    func doWork(data: *void)
    {
        for 3
        {
            #macro
            {
                let #alias0 = #up data
                let #alias1 = #up data
                #inject(#up stmt)
            }
        }
    }
    doWork(ctxData)
}

#[Swag.Macro]
func outerMacroDoubleInject(ctxData: *void = null, stmt: #code void)
{
    parallelVisitLike(ctxData)
    {
        #inject(#up stmt)
    }
}

#test
{
    var c = 0
    outerMacroDoubleInject(&c)
    {
        discard @atomadd(cast(*s32) #alias0, 1)
    }
    @assert(c == 3)
}
