#global private

alias RelaxedInlineS32 = s32

#[Swag.Inline]
func inlineTypedLocalAlias(value: s32)->s32
{
    var tmp: RelaxedInlineS32 = value + 1
    return tmp * 2
}

func autoTypedLocalAlias(value: s32)->s32
{
    var tmp: RelaxedInlineS32 = value + 1
    return tmp * 2
}

#[Swag.Inline]
func inlineTypedAccumulator(value: s32)->s32
{
    var acc: RelaxedInlineS32 = value
    acc += 2
    return acc
}

func autoTypedAccumulator(value: s32)->s32
{
    var acc: RelaxedInlineS32 = value
    acc += 2
    return acc
}

#test
{
    @assert(inlineTypedLocalAlias(20) == 42)
    @assert(autoTypedLocalAlias(20) == 42)

    @assert(inlineTypedAccumulator(40) == 42)
    @assert(autoTypedAccumulator(40) == 42)
}
