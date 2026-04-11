// 
#global fileprivate

#[Swag.Mixin]
func mixinFromCallerScope()
{
    total = value + delta
    let mixedValue: s32 = total * factor
}

#[Swag.Mixin]
func mixinInjectValue(value: s32, stmt: #code void)
{
    #inject(stmt)
    #inject(stmt)
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

func computeInjectedMixinTotal()->s32
{
    var total = 0
    mixinInjectValue(4, #code
    {
        total += value
    })

    mixinInjectValue(2)
    {
        total += value
    }

    return total
}

// Mixin accesses caller scope variables
#test
{
    @assert(computeWithMixin(41) == 42)
}

// Mixin-injected code can reference mixin parameters
#test
{
    @assert(computeInjectedMixinTotal() == 12)
}
