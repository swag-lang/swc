#global fileprivate
using Swag

#[Swag.Overload]
func getValue(type: typeinfo, attribute: typeinfo, value: string)->#null any
{
    let attrib = getAttr(type, attribute)
    if !attrib do
        return null
    return getValue(attrib, value)
}

#[Swag.Overload]
func(T) getValue(type: typeinfo, attribute: typeinfo, value: string, def: T)->T
{
    return def
}

#[Swag.Overload]
func getAttr(type: typeinfo, attribute: typeinfo)->#null const *Swag.Attribute
{
    return null
}

#[Swag.Overload]
func getValue(attribute: const *Swag.Attribute, value: string)->#null any
{
    return null
}

#test
{
    @assert(getValue(s32, s32, "x") == null)
}
