#global namespace Serialization

internal func getTypeValueCrc(val: Swag.TypeValue)->u32
{
    if val.crc do
        return val.crc
    if val.name == null do
        return 0
    return Hash.Crc32.compute(val.name)
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

// Returns the wire identity of a type, as written in a version 2 TagBin stream.
//
// The identity is chosen so the stream survives the type changes the format supports:
//
// - An enum is identified by its underlying type. Renaming an enum costs nothing, and
//   changing its underlying type becomes an ordinary native conversion instead of a
//   silently misread payload.
// - A named struct is identified by the crc of its full name. That crc can be computed
//   from a plain string, so a rename is declared with 'Serialization.Alias' rather than
//   recorded as a frozen hash constant.
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
