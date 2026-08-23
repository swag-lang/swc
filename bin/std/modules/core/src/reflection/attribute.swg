#global public
#global namespace Reflection

using Swag

// Returns whether two reflected attribute types identify the same declaration.
#[ConstExpr]
private func sameAttributeType(left: #null typeinfo, right: #null typeinfo)->bool
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
func attributeValue(type: #null const *Swag.TypeValue, attribute: #null typeinfo, value: #null string)->#null any
{
    let attrib = Reflection.attribute(type, attribute)
    if !attrib do
        return null
    return attributeValue(attrib, value)
}

// Returns the given attribute value, or null
#[ConstExpr]
func(T) attributeValue(type: #null const *Swag.TypeValue, attribute: #null typeinfo, value: #null string, defaultValue: T)->T
{
    let attrib = Reflection.attribute(type, attribute)
    if !attrib do
        return defaultValue
    let attribVal = attributeValue(attrib, value)
    if attribVal == null do
        return defaultValue
    return cast(T) attribVal
}

// Returns the given attribute value, or null
#[ConstExpr]
func attributeValue(type: #null typeinfo, attribute: #null typeinfo, value: #null string)->#null any
{
    let attrib = Reflection.attribute(type, attribute)
    if !attrib do
        return null
    return attributeValue(attrib, value)
}

// Returns the given attribute value, or null
#[ConstExpr]
func attributeValue(attribute: #null const *Swag.Attribute, value: #null string)->#null any
{
    if !attribute do
        return null
    for p in attribute.params where p.name == value do
        return p.value
    return null
}

// Returns the given associated attributes to 'value'
#[ConstExpr]
func attributes(value: #null const *Swag.TypeValue, attribute: #null typeinfo)->Array'(const *Swag.Attribute)
{
    var result: retval
    if !value do
        return result
    for &it in value.attributes where sameAttributeType(attribute, it.type) do
        result.add(it)
    return result
}

// Returns the given associated 'attribute' to 'value' or null
#[ConstExpr]
func attribute(value: #null const *Swag.TypeValue, attribute: #null typeinfo)->#null const *Swag.Attribute
{
    if !value do
        return null
    for &it in value.attributes where sameAttributeType(attribute, it.type) do
        return it
    return null
}

// Returns true if the given 'value' has the associated 'attribute'
#[ConstExpr]
func hasAttribute(value: #null const *Swag.TypeValue, attribute: #null typeinfo)->bool
{
    return Reflection.attribute(value, attribute) != null
}

// Returns the given associated attributes to 'type'
#[ConstExpr]
func attributes(type: #null typeinfo, attribute: #null typeinfo)->Array'(const *Swag.Attribute)
{
    var result: retval
    if !type do
        return result

    let safeType = type
    switch safeType.kind
    {
    case .Func:
        let typeFunc = cast(const *TypeInfoFunc) safeType
        for &it in typeFunc.attributes where sameAttributeType(attribute, it.type) do
            result.add(it)

    case .Struct:
        let typeStruct = cast(const *TypeInfoStruct) safeType
        for &it in typeStruct.attributes where sameAttributeType(attribute, it.type) do
            result.add(it)

    case .Enum:
        let typeEnum = cast(const *TypeInfoEnum) safeType
        for &it in typeEnum.attributes where sameAttributeType(attribute, it.type) do
            result.add(it)
    }

    return result
}

// Returns the given associated 'attribute' to 'type' or null
#[ConstExpr]
func attribute(type: #null typeinfo, attribute: #null typeinfo)->#null const *Swag.Attribute
{
    if !type do
        return null

    let safeType = type
    switch safeType.kind
    {
    case .Func:
        let typeFunc = cast(const *TypeInfoFunc) safeType
        for &it in typeFunc.attributes where sameAttributeType(attribute, it.type) do
            return it

    case .Struct:
        let typeStruct = cast(const *TypeInfoStruct) safeType
        for &it in typeStruct.attributes where sameAttributeType(attribute, it.type) do
            return it

    case .Enum:
        let typeEnum = cast(const *TypeInfoEnum) safeType
        for &it in typeEnum.attributes where sameAttributeType(attribute, it.type) do
            return it
    }

    return null
}

// Returns true if the given 'type' has the associated 'attribute'
#[ConstExpr]
func hasAttribute(type: #null typeinfo, attribute: #null typeinfo)->bool
{
    return Reflection.attribute(type, attribute) != null
}
