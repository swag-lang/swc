#global fileprivate

#[Swag.Mixin]
func mixinFromCallerScope()
{
    total = value + delta
    let mixedValue: s32 = total * factor
}

func computeWithMixin(value: s32)->s32
{
    var total: s32 = 0
    let delta: s32 = 1
    let factor: s32 = 2

    mixinFromCallerScope()

    @assert(total == 42)
    @assert(mixedValue == 84)
    return total
}

#test
{
    @assert(computeWithMixin(41) == 42)
}
