#global private

var G:          s32 = 0
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
func macroInject(stmt: #code)
{
    #inject(stmt)
}

#[Swag.Mixin]
func mixinConditionalDefer(shouldFail: bool) fail
{
    defer #fail appendDeferTrace(1)
    defer #nofail appendDeferTrace(2)
    if shouldFail do
        fail ErrCompilerDefer{}
}

func semaTest001()
{
    mixinDeferredGlobal()
}

func semaTest002()
{
    var value = 0
    macroInject(#code {
        defer value = 1
    })
}

func semaTest003()
{
    var value = 0
    for 1
    {
        macroInject(#code {
            defer value += 1
        })
    }
}

func semaTest004()
{
    func runMixinConditionalDefer(shouldFail: bool)->s64
    {
        resetDeferTrace()
        catch mixinConditionalDefer(shouldFail)
        return DeferTrace
    }

    const failureTrace = #run runMixinConditionalDefer(true)
    const successTrace = #run runMixinConditionalDefer(false)
    #assert(failureTrace == 1)
    #assert(successTrace == 2)
}
