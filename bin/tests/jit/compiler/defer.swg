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
