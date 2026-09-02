#global namespace Serialization

// Returns the canonical wire key of a field. Explicit keys survive source renames;
// unannotated fields retain the source name as their wire key.
internal func wireFieldKey(val: Swag.TypeValue)->string
{
    // Inspect the field's own attribute slice. Going through the overload that also
    // accepts `typeinfo` can select the enclosing struct and leak a type-level
    // attribute onto every field.
    let keyType = #typeof(Serialization.Key)
    for &attribute in val.attributes
    {
        if !attribute.type do
            continue
        if attribute.type.fullname != keyType.fullname do
            continue
        let key = Reflection.attributeValue(attribute, "name")
        if key != null do
            return cast(string) key!
    }

    if val.name == null do
        return ""
    return val.name
}

// Returns the canonical schema of a root type, or an empty schema when the type does
// not opt into document identity checks.
internal func wireSchema(type: #null typeinfo)->string
{
    if !type do
        return ""
    let schema = Reflection.attributeValue(type!, Serialization.Schema, "name")
    if schema == null do
        return ""
    return cast(string) schema!
}

// Returns the explicit stable key of a struct type.
internal func wireTypeKey(type: #null typeinfo)->string
{
    if !type do
        return ""
    let key = Reflection.attributeValue(type!, Serialization.TypeKey, "name")
    if key == null do
        return ""
    return cast(string) key!
}

internal func getTypeInfoCrc(type: #null typeinfo)->u32
{
    if !type do
        return 0
    if type.crc do
        return type.crc
    if type.fullname != null and type.fullname != "" do
        return Hash.Crc32.compute(type.fullname)
    if type.name == null do
        return 0
    return Hash.Crc32.compute(type.name)
}

// Returns the wire identity of a statically declared field type.
//
// The identity is chosen so the stream survives the type changes the format supports:
//
// - An enum is identified by its underlying type. Renaming an enum costs nothing, and
//   changing its underlying type becomes an ordinary native conversion instead of a
//   silently misread payload.
// - A named struct is identified by the crc of its full name. A renamed struct can still
//   be decoded through its statically requested type because structured payloads are
//   self-framed. Dynamic interface objects use [[wireTypeKey]] instead.
// - Everything else keeps the canonical runtime crc of the type.
internal func wireTypeCrc(type: #null typeinfo)->u32
{
    if !type do
        return 0

    let resolved = Reflection.resolveAliases(type!)
    if Reflection.isEnum(resolved) do
        return wireTypeCrc(Reflection.enumUnderlyingType(resolved))

    if Reflection.isStruct(resolved) and !Reflection.isTuple(resolved)
    {
        if resolved.fullname != null and resolved.fullname != "" do
            return Hash.Crc32.compute(resolved.fullname)
        if resolved.name != null and resolved.name != "" do
            return Hash.Crc32.compute(resolved.name)
    }

    return getTypeInfoCrc(resolved)
}

// Determin if a type can be serialized by a simple copy
public func isPodFinal(type: #null typeinfo)->{ raw: bool, sizeof: u64 }
{
    if type
    {
        if Reflection.isInteger(type) or
           Reflection.isFloat(type) or
           Reflection.isBool(type) or
           Reflection.isRune(type)
        {
            return {true, type.sizeof}
        }

        if !Reflection.isPod(type) do
            return {false, 0}

        if Reflection.hasAttribute(type, Serialization.Final) do
            return {true, type.sizeof}
    }

    return {false, 0}
}
