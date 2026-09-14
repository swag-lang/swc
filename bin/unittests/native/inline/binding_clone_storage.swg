#global private

#[Swag.Macro]
func invokeTwice(callback: func||()->s32)->s32 => callback() + callback()

#[Swag.Macro]
func invokeWithValue(callback: func||(value: s32)->s32, value: s32)->s32 => callback(value)

#[Swag.NoInline]
func clonedLocals(seed: s32)->s32
{
    var total = 1000
    let result = invokeTwice(func|seed|()->s32
    {
        func double(value: s32)->s32 => value * 2
        var total = seed
        total += 7
        total *= 3
        return double(total)
    })
    Swag.assert(total == 1000)
    return result
}

#[Swag.NoInline]
func clonedParameters(seed: s32)->s32
{
    return invokeWithValue(func|seed|(value: s32)->s32
    {
        var total = seed
        total += value
        return total
    }, 11)
}

#test
{
    for seed in [0, 1, 3, 19]
    {
        Swag.assert(clonedLocals(seed) == (seed + 7) * 12)
        Swag.assert(clonedParameters(seed) == seed + 11)
    }
}
