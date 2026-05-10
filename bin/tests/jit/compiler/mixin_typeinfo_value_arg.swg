#global fileprivate

func(T) mixinTypeInfoValueArg()->bool
{
    #[Swag.Mixin]
    func matches(typeField: typeinfo)->bool
    {
        return typeField == #typeof(T)
    }

    let current = #typeof(T)
    return matches(current)
}

#test
{
    @assert(mixinTypeInfoValueArg's32())
    @assert(mixinTypeInfoValueArg'bool())
}
