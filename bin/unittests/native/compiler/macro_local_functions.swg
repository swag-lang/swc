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
        return value * 2
    }

    return emit(seed)
}

#[Swag.Macro]
func aliasBounce(value: s32)->s32
{
    return value + 1
}

#[Swag.Macro]
func localNestedShadow(seed: s32)->s32
{
    // 'pick' has its own 'value' parameter: 'value' inside 'aliasBounce'
    // must resolve to that macro's own parameter, not to this local function's
    // same-named parameter at the expansion site.
    func pick(seed: s32, value: s32)->s32
    {
        return aliasBounce(seed)
    }

    return pick(seed, 1000)
}

func forcedLocalMacroRelay(seed: s32)->s32
{
    #[Swag.Macro]
    func emit(value: s32)->s32
    {
        return value * 3
    }

    return emit(seed)
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
        // Hygiene: this block resolves in the outer macro's scope, so 'stmt'
        // is the outer macro's parameter; 'ctx' is the bound block parameter.
        #inject(stmt, data = ctx)
    }
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
    @assert(localNestedShadow(41) == 42)
}

#test
{
    @assert(forcedLocalMacroRelay(14) == 42)
}

#test
{
    var runs = 0
    localForMacroInject(3, &runs)
    {
        discard @atomadd(cast(*s32) data, 1)
    }
    @assert(runs == 3)
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
