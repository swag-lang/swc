#global private
using Swag

#[AttrUsage(AttributeUsage.Function)]
attr LocalContextTag(value: s32)

#[Macro]
func reflectLocalContext()->s32
{
    #[LocalContextTag(73)]
    func localValue()->s32
    {
        return 7
    }

    let info = cast(const *TypeInfoFunc) #typeof(localValue)
    Swag.assert(info.attributes.count == 1)
    Swag.assert(info.attributes[0].type == #typeof(LocalContextTag))
    Swag.assert(cast #assume(s32) info.attributes[0].params[0].value == 73)
    return localValue()
}

#test
{
    Swag.assert(reflectLocalContext() == 7)
}
