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

func getAttr(_: typeinfo, _: typeinfo)->const *Swag.Attribute?
{
    return null
}

func getValue(_: const *Swag.Attribute, _: string)->any?
{
    return null
}

func semaTest001()
{
    Swag.assert(getValue(s32, s32, "x") == null)
}
