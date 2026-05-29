#global fileprivate

#[Swag.Macro]
func(T) localGenericSignature(value: T)->T
{
    func typedIdentity(input: T)->T
    {
        return input
    }

    return typedIdentity(value)
}

#[Swag.Macro]
func localMacroRelay(seed: s32)->s32
{
    func emit(value: s32)->s32
    {
        #macro
        {
            return #up value * 2
        }
    }

    return emit(seed)
}

#[Swag.Macro]
func aliasBounce(value: s32)->s32
{
    #macro
    {
        let #alias0 = #up value
        #macro
        {
            return #up buffer + 1
        }
    }
}

#[Swag.Macro]
func localNestedUpShadow(seed: s32)->s32
{
    func pick(buffer: s32)->s32
    {
        return aliasBounce(|buffer| #up seed)
    }

    return pick(1000)
}

#test
{
    @assert(localGenericSignature(41) == 41)
}

#test
{
    @assert(localMacroRelay(21) == 42)
}

#test
{
    @assert(localNestedUpShadow(41) == 42)
}
