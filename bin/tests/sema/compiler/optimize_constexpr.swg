#global fileprivate

const Cfg = #run dref @compiler.getBuildCfg()

func pureAdd(a: s32, b: s32)->s32
{
    var sum: s32 = a + b
    return sum
}

#[Swag.Inline]
func inlineTypedVariadicCount(values: s32...)->s32 => cast(s32) @countof(values)

#[Swag.Macro]
func macroAdd(a: s32, b: s32)->s32 => a + b

func defaultPureArg(value: s32 = pureAdd(40, 2))->s32
{
    return value
}

#if pureAdd(20, 22) == 42
{
    const CompilerIfConstexpr = true
}
#else
{
    const CompilerIfConstexpr = false
}

const PureConstexpr = pureAdd(40, 2)

alias FixedArray = [pureAdd(20, 22)] s32

#assert(CompilerIfConstexpr)
#assert(PureConstexpr == 42)
#assert(#sizeof(FixedArray) == 42 * #sizeof(s32))

#test
{
    @assert(defaultPureArg() == 42)
    @assert(#isconstexpr(macroAdd(20, 22)))

    if Cfg.backend.optimize
    {
        @assert(#isconstexpr(pureAdd(20, 22)))
        @assert(#isconstexpr(inlineTypedVariadicCount(20, 20, 2)))
    }
    else
    {
        @assert(!#isconstexpr(pureAdd(20, 22)))
        @assert(!#isconstexpr(inlineTypedVariadicCount(20, 20, 2)))
    }
}
