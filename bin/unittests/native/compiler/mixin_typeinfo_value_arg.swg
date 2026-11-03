#global private

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
    Swag.require(mixinTypeInfoValueArg's32())
    Swag.require(mixinTypeInfoValueArg'bool())
}
