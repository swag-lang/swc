#global private

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
        return #up value + 1
    }
}

#[Swag.Macro]
func localNestedUpShadow(seed: s32)->s32
{
    // 'pick' has its own 'value' parameter: '#up value' inside 'aliasBounce'
    // must resolve to the macro's parameter, not to this caller-scope local.
    func pick(seed: s32, value: s32)->s32
    {
        return aliasBounce(#up seed)
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

// Tests for #inject inside a for loop inside a local function.
// Verifies the codegen fix for inline-label placement in locally-compiled functions.
// This is the exact pattern used by Jobs.parallelVisit / Jobs.parallelFor.
#[Swag.Macro]
func localForMacroInject(count: s32, contextData: *void = null, stmt: #code(data: *void, data2: *void))
{
    func doWork(n: s32, ctxData: *void)
    {
        for n
        {
            #inject(stmt, data = ctxData, data2 = ctxData)
        }
    }

    doWork(count, contextData)
}

#test
{
    // Verify that #inject inside a for loop in a local function runs correctly
    var runs = 0
    localForMacroInject(3, &runs)
    {
        discard @atomadd(cast(*s32) data, 1)
    }
    @assert(runs == 3)
}

// Verifies two-level nested macro injection (outer macro → local-function for loop)
// correctly handles 'return' inside the injected code block via doneLabel placement.
#[Swag.Macro]
func parallelVisitLike(ctxData: *void = null, stmt: #code(ctx: *void, ctx2: *void))
{
    func doWork(payload: *void)
    {
        for 3
        {
            #inject(stmt, ctx = payload, ctx2 = payload)
        }
    }
    doWork(ctxData)
}

#[Swag.Macro]
func outerMacroDoubleInject(ctxData: *void = null, stmt: #code(data: *void))
{
    parallelVisitLike(ctxData)
    {
        #inject(#up stmt, data = ctx)
    }
}

#test
{
    var c = 0
    outerMacroDoubleInject(&c)
    {
        discard @atomadd(cast(*s32) data, 1)
    }
    @assert(c == 3)
}
