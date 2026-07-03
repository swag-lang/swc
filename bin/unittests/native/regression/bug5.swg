#global private

#[Swag.Inline]
func addShadowedInlineArg(value: s32)->s32
{
    var local = 100
    return value + local
}

func runInlineCallerParamShadow(value: s32)->s32
{
    var local = value
    return addShadowedInlineArg(local)
}

#[Swag.Inline]
func addTwoShadowedInlineArgs(left: s32, right: s32)->s32
{
    var local = 100
    var other = 1000
    return left + right + local + other
}

func runInlineMultipleCallerParamShadow(left: s32, right: s32)->s32
{
    var local = left
    var other = right
    return addTwoShadowedInlineArgs(local, other)
}

#[Swag.Inline]
func addGroupedShadowedInlineArgs(left, right: s32)->s32
{
    var local = 100
    var other = 1000
    return left + right + local + other
}

func runInlineGroupedParamShadow(left: s32, right: s32)->s32
{
    var local = left
    var other = right
    return addGroupedShadowedInlineArgs(local, other)
}

#test
{
    @assert(runInlineCallerParamShadow(7) == 107)
    @assert(runInlineMultipleCallerParamShadow(3, 4) == 1107)
    @assert(runInlineGroupedParamShadow(3, 4) == 1107)
}
