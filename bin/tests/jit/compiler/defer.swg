#global fileprivate

var DeferTrace: s64 = 0

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

var MacroState: s32 = 0
var ScopeLockValue: s32 = 0

/*
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
*/

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

#test
{
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

    const V = #run runInjectedFunctionScopeTrace()
    #assert(V.value == 42)
    #assert(V.trace == 1982)
}

#test
{
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

    const V = #run runInjectedLoopScope()
    #assert(V == 818181)
}

/*
#test
{
    // compiler2240
    func runMixinScopeLock()->s32
    {
        ScopeLockValue = 0
        {
            mixinScopeLock()
            defer a += 1
        }

        return ScopeLockValue
    }

    const V = #run runMixinScopeLock()
    #assert(V == 5)
}

#test
{
    // compiler2636, compiler3747
    func runMixinParamTrace()->s64
    {
        resetDeferTrace()
        mixinParamTrace(5)
        appendDeferTrace(2)
        return DeferTrace
    }

    const V = #run runMixinParamTrace()
    #assert(V == 215)
}

#test
{
    // compiler2805
    func runMacroScopeTrace()->s64
    {
        resetDeferTrace()
        macroScope()
        {
            appendDeferTrace(1)
        }

        return DeferTrace
    }

    const V = #run runMacroScopeTrace()
    #assert(V == 17)
}

#test
{
    // compiler2195
    MacroState = 0
    const V = macroString("toto")
    #assert(V == "toto")
    #assert(MacroState == 1)
}
*/

// Legacy cases intentionally left commented until #err/#noerr/catch defer modes land.
// compiler3719
// compiler3775
// compiler5208
