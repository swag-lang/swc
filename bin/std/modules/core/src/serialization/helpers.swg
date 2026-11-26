#global namespace Serialization

// Returns the run of JSON string bytes that can be copied verbatim.
internal func jsonPlainByteCount(bytes: const [..] u8)->u64
{
    const VectorSize = #sizeof(Simd.U8x16)
    var length = 0'u64
    if bytes.count >= VectorSize
    {
        let control   = Simd.splat(0x20'u8)
        let quote     = Simd.splat('"'u8)
        let backslash = Simd.splat('\\'u8)
        while bytes.count - length >= VectorSize
        {
            let block   = Simd.load(bytes.buffer + length)
            let special = Simd.bitmask((block < control) | (block == quote) | (block == backslash))
            if special do
                return length + Math.trailingZeros(special)
            length += VectorSize
        }
    }

    while length < bytes.count
    {
        let byte = bytes[length]
        if byte < 0x20 or byte == '"' or byte == '\\' do
            break
        length += 1
    }

    return length
}

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
        if not attribute.type
        {
            continue
        }

        if attribute.type.fullname != keyType.fullname
        {
            continue
        }

        let key = Reflection.attributeValue(attribute, "name")
        if key != null
        {
            return assume cast (string, key)
        }
    }

    return val.name orelse ""
}

// Returns the canonical schema of a root type, or an empty schema when the type does
// not opt into document identity checks.
internal func wireSchema(type: typeinfo?)->string
{
    if not type
    {
        return ""
    }

    let schema = Reflection.attributeValue(type, Serialization.Schema, "name")
    if schema == null
    {
        return ""
    }

    return assume cast (string, schema)
}

// Returns the explicit stable key of a struct type.
internal func wireTypeKey(type: typeinfo?)->string
{
    if not type
    {
        return ""
    }

    let key = Reflection.attributeValue(type, Serialization.TypeKey, "name")
    if key == null
    {
        return ""
    }

    return assume cast (string, key)
}

internal func getTypeInfoCrc(type: typeinfo?)->u32
{
    if not type
    {
        return 0
    }

    if type.crc
    {
        return type.crc
    }

    if type.fullname != null and type.fullname != ""
    {
        return Hash.Crc32.compute(type.fullname)
    }

    if type.name == null
    {
        return 0
    }

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
internal func wireTypeCrc(type: typeinfo?)->u32
{
    if not type
    {
        return 0
    }

    let resolved = Reflection.resolveAliases(type)
    if Reflection.isEnum(resolved)
    {
        return wireTypeCrc(Reflection.enumUnderlyingType(resolved))
    }

    if Reflection.isStruct(resolved) and not Reflection.isTuple(resolved)
    {
        if resolved.fullname != null and resolved.fullname != ""
        {
            return Hash.Crc32.compute(resolved.fullname)
        }

        if resolved.name != null and resolved.name != ""
        {
            return Hash.Crc32.compute(resolved.name)
        }
    }

    return getTypeInfoCrc(resolved)
}

// Returns whether values of `type` serialize as a raw copy of their bytes, with their size in bytes.
//
// Integers, floats, Booleans, runes, and enums backed by those types do, as does a
// plain-data struct marked [[Core.Serialization.Final]]. Other types return false and zero.
public func isPodFinal(type: typeinfo?)->{ raw: bool, sizeof: u64 }
{
    if type
    {
        if Reflection.isInteger(type) or
           Reflection.isFloat(type) or
           Reflection.isBool(type) or
           Reflection.isRune(type)
        {
            return {raw: true, sizeof: type.sizeof}
        }

        if Reflection.isEnum(type) and Reflection.isPod(type)
        {
            let enumType = assume cast(const *TypeInfoEnum, type)
            let rawType  = enumType.rawType
            if Reflection.isInteger(rawType) or
               Reflection.isFloat(rawType) or
               Reflection.isBool(rawType) or
               Reflection.isRune(rawType)
            {
                return {raw: true, sizeof: type.sizeof}
            }
        }

        if not Reflection.isPod(type)
        {
            return {raw: false, sizeof: 0}
        }

        if Reflection.hasAttribute(type, Serialization.Final)
        {
            return {raw: true, sizeof: type.sizeof}
        }
    }

    return {raw: false, sizeof: 0}
}
