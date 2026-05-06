#global fileprivate

#[Swag.Mixin]
func mixinTypedVariadicClosure(values: s32...)->s32
{
    let cb = func|values|()->s32
    {
        return values[0] + values[1] + values[2]
    }

    return cb()
}

func runMixinTypedVariadicClosure()->s32
{
    return mixinTypedVariadicClosure(10, 20, 30)
}

#test
{
    const value = #run runMixinTypedVariadicClosure()
    #assert(value == 60)
}
