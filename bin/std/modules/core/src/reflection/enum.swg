#global public
#global namespace Reflection

using Swag

// Returns an enum's underlying native type, or the input type when it is not an enum.
#[ConstExpr]
func enumUnderlyingType(type: typeinfo)->typeinfo
{
    if !isEnum(type) do
        return type

    let enumType = cast(const *TypeInfoEnum) type
    return enumType.rawType!
}

// Returns reflected information for a named enum value, or null.
#[ConstExpr]
func enumValue(type: #null typeinfo, name: #null string)->#null const *TypeValue
{
    if !isEnum(type) do
        return null

    let typeEnum = cast(const *TypeInfoEnum) type!
    for &it in typeEnum.values where it.name == name do
        return it
    return null
}

// Returns the enum name for a value. Flag values can produce multiple names.
#[ConstExpr]
func enumName(type: #null typeinfo, valueAddress: #null const *void, fullyQualified = true)->String
{
    var result: String
    if !isEnum(type) or !valueAddress do
        return result
    let safeType  = type!
    let safeValue = valueAddress
    let typeEnum  = cast(const *TypeInfoEnum) safeType
    let rawType   = typeEnum.rawType!
    let isFlags   = hasAttribute(type, EnumFlags)

    // Get the user value, as an 'u64' or a string
    var val1:  u64
    var val1s: #null string
    switch rawType.sizeof
    {
    case 1:  val1 = cast(u64) dref cast(const *u8) safeValue
    case 2:  val1 = cast(u64) dref cast(const *u16) safeValue
    case 4:  val1 = cast(u64) dref cast(const *u32) safeValue
    case 8:  val1 = cast(u64) dref cast(const *u64) safeValue
    case 16: val1s = dref cast(const *#null string) safeValue
    default: return result
    }

    let simpleName = safeType.name

    for it in typeEnum.values
    {
        if !it.value do
            continue
        let safeItValue = it.value

        // Get the enum value, as an 'u64' or a string
        var val2:  u64
        var val2s: #null string
        switch rawType.sizeof
        {
        case 1:  val2 = cast(u64) dref cast(const *u8) safeItValue
        case 2:  val2 = cast(u64) dref cast(const *u16) safeItValue
        case 4:  val2 = cast(u64) dref cast(const *u32) safeItValue
        case 8:  val2 = cast(u64) dref cast(const *u64) safeItValue
        case 16: val2s = dref cast(const *#null string) safeItValue
        }

        // For a normal enum, stop if this is a match
        if !isFlags and val1 == val2 and val1s == val2s
        {
            if fullyQualified
            {
                result += simpleName
                result += "."
            }

            result += it.name
            return result
        }

        // For a flags enum, just append the name if the bit is set
        if isFlags and (val1 & val2)
        {
            if !result.isEmpty() do
                result += " | "

            if fullyQualified
            {
                result += simpleName
                result += "."
            }

            result += it.name
        }
    }

    return result
}
