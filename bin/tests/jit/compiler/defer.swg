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

struct ErrCompilerDefer {}

#[Swag.Mixin]
func mixinAddDefer()
{
    defer appendDeferTrace(9)
    appendDeferTrace(1)
}

var MacroState: s32 = 0
var ScopeLockValue: s32 = 0

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

#[Swag.Mixin]
func mixinConditionalDefer(shouldThrow: bool) throw
{
    defer #err appendDeferTrace(1)
    defer #noerr appendDeferTrace(2)
    if shouldThrow do
        throw ErrCompilerDefer{}
}

#[Swag.Macro]
func macroRun(stmt: #code void)
{
    #inject(stmt)
}

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
    #assert(V.trace == 1829)
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

#test
{
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
    func runMixinParamTrace()->s64
    {
        resetDeferTrace()
        mixinParamTrace(5)
        appendDeferTrace(2)
        return DeferTrace
    }

    const V = #run runMixinParamTrace()
    #assert(V == 12)
}

#test
{
    func runMixinConditionalDefer(shouldThrow: bool)->s64
    {
        resetDeferTrace()
        catch mixinConditionalDefer(shouldThrow)
        return DeferTrace
    }

    const failureTrace = #run runMixinConditionalDefer(true)
    const successTrace = #run runMixinConditionalDefer(false)
    #assert(failureTrace == 1)
    #assert(successTrace == 2)
}
