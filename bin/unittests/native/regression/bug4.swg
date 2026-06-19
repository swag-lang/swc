#global fileprivate

#[Swag.Inline]
func addShadowedInlineArg(value: s32)->s32
{
    var local = 100
    return value + local
}

func runInlineLocalShadow(input: s32)->s32
{
    var local = input
    return addShadowedInlineArg(local)
}

#test
{
    @assert(runInlineLocalShadow(7) == 107)
}
