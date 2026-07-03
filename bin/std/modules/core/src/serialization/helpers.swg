#global namespace Serialization

internal func getTypeValueCrc(val: Swag.TypeValue)->u32
{
    if val.crc do
        return val.crc
    return Hash.Crc32.compute(val.name)
}

internal func getTypeInfoCrc(type: typeinfo)->u32
{
    if type.crc do
        return type.crc
    if type.fullname != null and type.fullname != "" do
        return Hash.Crc32.compute(type.fullname)
    return Hash.Crc32.compute(type.name)
}

// Determin if a type can be serialized by a simple copy
public func isPodFinal(type: #null typeinfo)->{ raw: bool, sizeof: u64 }
{
    if type != null
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
