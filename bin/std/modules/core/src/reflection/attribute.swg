#global public
#global namespace Reflection
using Swag

#[ConstExpr]
func sameAttributeType(left: typeinfo, right: typeinfo)->bool
{
    if left == null or right == null do
        return false
    if left.fullname != null and right.fullname != null and left.fullname != "" and right.fullname != "" do
        return left.fullname == right.fullname
    if left.name != null and right.name != null and left.name != "" and right.name != "" do
        return left.name == right.name
    return false
}

// Returns the given attribute value, or null
#[ConstExpr]
func getAttributeValue(type: const *Swag.TypeValue, attribute: typeinfo, value: string)->#null any
{
    let attrib = getAttribute(type, attribute)
    if !attrib do
        return null
    return getAttributeValue(attrib, value)
}

// Returns the given attribute value, or null
#[ConstExpr]
func(T) getAttributeValue(type: const *Swag.TypeValue, attribute: typeinfo, value: string, def: T)->T
{
    let attrib = getAttribute(type, attribute)
    if !attrib do
        return def
    let attribVal = getAttributeValue(attrib, value)
    if attribVal == null do
        return def
    return cast(T) attribVal
}

// Returns the given attribute value, or null
#[ConstExpr]
func getAttributeValue(type: typeinfo, attribute: typeinfo, value: string)->#null any
{
    let attrib = getAttribute(type, attribute)
    if !attrib do
        return null
    return getAttributeValue(attrib, value)
}

// Returns the given attribute value, or null
#[ConstExpr]
func getAttributeValue(attribute: const *Swag.Attribute, value: string)->#null any
{
    for p in attribute.params where p.name == value do
        return p.value
    return null
}

// Returns the given associated attributes to 'value'
#[ConstExpr]
func getAttributes(value: const *Swag.TypeValue, attribute: typeinfo)->Array'(const *Swag.Attribute)
{
    var result: retval
    for &it in value.attributes where sameAttributeType(attribute, it.type) do
        result.add(it)
    return result
}

// Returns the given associated 'attribute' to 'value' or null
#[ConstExpr]
func getAttribute(value: const *Swag.TypeValue, attribute: typeinfo)->#null const *Swag.Attribute
{
    for &it in value.attributes where sameAttributeType(attribute, it.type) do
        return it
    return null
}

// Returns true if the given 'value' has the associated 'attribute'
#[ConstExpr]
func hasAttribute(value: const *Swag.TypeValue, attribute: typeinfo)->bool
{
    return getAttribute(value, attribute) != null
}

// Returns the given associated attributes to 'type'
#[ConstExpr]
func getAttributes(type: typeinfo, attribute: typeinfo)->Array'(const *Swag.Attribute)
{
    var result: retval
    switch type.kind
    {
    case Func:
        let typeFunc = cast(const *TypeInfoFunc) type
        for &it in typeFunc.attributes where sameAttributeType(attribute, it.type) do
            result.add(it)

    case Struct:
        let typeStruct = cast(const *TypeInfoStruct) type
        for &it in typeStruct.attributes where sameAttributeType(attribute, it.type) do
            result.add(it)

    case Enum:
        let typeEnum = cast(const *TypeInfoEnum) type
        for &it in typeEnum.attributes where sameAttributeType(attribute, it.type) do
            result.add(it)
    }

    return result
}

// Returns the given associated 'attribute' to 'type' or null
#[ConstExpr]
func getAttribute(type: typeinfo, attribute: typeinfo)->#null const *Swag.Attribute
{
    switch type.kind
    {
    case Func:
        let typeFunc = cast(const *TypeInfoFunc) type
        for &it in typeFunc.attributes where sameAttributeType(attribute, it.type) do
            return it

    case Struct:
        let typeStruct = cast(const *TypeInfoStruct) type
        for &it in typeStruct.attributes where sameAttributeType(attribute, it.type) do
            return it

    case Enum:
        let typeEnum = cast(const *TypeInfoEnum) type
        for &it in typeEnum.attributes where sameAttributeType(attribute, it.type) do
            return it
    }

    return null
}

// Returns true if the given 'type' has the associated 'attribute'
#[ConstExpr]
func hasAttribute(type: typeinfo, attribute: typeinfo)->bool
{
    return getAttribute(type, attribute) != null
}
