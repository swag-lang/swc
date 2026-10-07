#global private
using Swag

func getValue(type: typeinfo, attribute: typeinfo, value: string)->any?
{
    let attrib = getAttr(type, attribute)
    if not attrib do
        return null
    return getValue(attrib, value)
}

func(T) getValue(type: typeinfo, attribute: typeinfo, value: string, def: T)->T
{
    return def
}

func getAttr(?: typeinfo, ?: typeinfo)->const *Swag.Attribute?
{
    return null
}

func getValue(?: const *Swag.Attribute, ?: string)->any?
{
    return null
}

func semaTest001()
{
    Swag.assert(getValue(s32, s32, "x") == null)
}
