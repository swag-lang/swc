#global fileprivate

var G: s32 = 0
var DeferTrace: s64 = 0

func resetDeferTrace()
{
    DeferTrace = 0
}

func appendDeferTrace(value: s64)
{
    DeferTrace = DeferTrace * 10 + value
}

struct ErrCompilerDefer {}

#[Swag.Mixin]
func mixinDeferredGlobal()
{
    defer G = 1
}

#[Swag.Macro]
func macroInject(stmt: #code void)
{
    #inject(stmt)
}

#[Swag.Mixin]
func mixinConditionalDefer(shouldThrow: bool) throw
{
    defer #err appendDeferTrace(1)
    defer #noerr appendDeferTrace(2)
    if shouldThrow do
        throw ErrCompilerDefer{}
}

#test
{
    mixinDeferredGlobal()
}

#test
{
    var value = 0
    macroInject(#code {
        defer value = 1
    })
}

#test
{
    var value = 0
    for 1
    {
        macroInject(#code {
            defer value += 1
        })
    }
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
