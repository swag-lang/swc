#global fileprivate

var DeferTrace: s64 = 0
var MacroState: s32 = 0
var ScopeLockValue: s32 = 0

func resetDeferTrace()
{
    DeferTrace = 0
}

func appendDeferTrace(value: s64)
{
    DeferTrace = DeferTrace * 10 + value
}

struct CompilerDeferReturnInfo
{
    value: s32
    trace: s64
}

#[Swag.Mixin]
func mixinAddDefer()
{
    defer appendDeferTrace(9)
    appendDeferTrace(1)
}

#[Swag.Mixin]
func mixinScopeLock()
{
    var a = 4
    defer ScopeLockValue = a
}

#[Swag.Mixin]
func mixinParamTrace(value: s64)
{
    defer appendDeferTrace(value)
    appendDeferTrace(1)
}

#[Swag.Macro]
func macroRun(stmt: #code void)
{
    #inject(stmt)
}

/*
#[Swag.Macro]
func macroScope(stmt: #code void)
{
    #macro
    {
        var x = 0's64
        defer appendDeferTrace(7)
        #inject(#up stmt)
    }
}

#[Swag.Macro]
func macroString(x: string)->string
{
    defer MacroState = 1
    return "toto"
}
*/

func runInjectedFunctionScopeTrace()->CompilerDeferReturnInfo
{
    resetDeferTrace()
    with var result: retval
    {
        .value = 42
        .trace = -1
    }

    defer result.trace = DeferTrace
    mixinAddDefer()
    macroRun(#code {
        defer appendDeferTrace(8)
    })
    appendDeferTrace(2)
    return result
}

func runInjectedLoopScope()->s64
{
    resetDeferTrace()
    for 3
    {
        macroRun(#code {
            defer appendDeferTrace(8)
        })
        appendDeferTrace(1)
    }

    return DeferTrace
}

func runMixinScopeLock()->s32
{
    ScopeLockValue = 0
    {
        mixinScopeLock()
        defer a += 1
    }

    return ScopeLockValue
}

func runMixinParamTrace()->s64
{
    resetDeferTrace()
    mixinParamTrace(5)
    appendDeferTrace(2)
    return DeferTrace
}

/*
func runMacroScopeTrace()->s64
{
    resetDeferTrace()
    macroScope()
    {
        appendDeferTrace(1)
    }

    return DeferTrace
}
*/

// Defer ordering with injected and mixin scopes
#test
{
    let v = runInjectedFunctionScopeTrace()
    @assert(v.value == 42)
    @assert(v.trace == 1829)
}

// Defer in injected loop scope repeats per iteration
#test
{
    @assert(runInjectedLoopScope() == 818181)
}

// Mixin defer runs at end of enclosing scope
#test
{
    @assert(runMixinScopeLock() == 5)
}

// Mixin with param defers after body
#test
{
    @assert(runMixinParamTrace() == 12)
}

/*
#test
{
    @assert(runMacroScopeTrace() == 17)
}

#test
{
    MacroState = 0
    let v = macroString("toto")
    @assert(v == "toto")
    @assert(MacroState == 1)
}
*/

// Legacy cases intentionally left commented until #err/#noerr/catch defer modes land.
// compiler3719
// compiler3775
// compiler5208
