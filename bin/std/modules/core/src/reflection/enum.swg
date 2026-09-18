#global public
#global namespace Reflection

using Swag

// Returns an enum's underlying native type, or the input type when it is not an enum.
#[ConstExpr]
func enumUnderlyingType(type: typeinfo)->typeinfo
{
    if not isEnum(type) do
        return type

    let enumType = cast #assume(const *TypeInfoEnum) type
    return enumType.rawType!
}

// Returns reflected information for a named enum value, or null.
#[ConstExpr]
func enumValue(type: typeinfo?, name: string?)->const *TypeValue?
{
    if not isEnum(type) do
        return null

    let typeEnum = cast #assume(const *TypeInfoEnum) type!
    for &it in typeEnum.values where it.name == name do
        return it
    return null
}

// Returns the name of the case of enum `type` whose value is stored at `valueAddress`.
//
// For an enum marked `#[Swag.EnumFlags]`, returns the name of every case whose bits are all
// set in the value, separated by ` | `; a case adding no bit to the ones already named, such as
// an alias or a combination, is skipped, and zero is named only by a case whose value is zero. With `fullyQualified`, each name is prefixed by the enum type name, as in
// `Color.Red`. Returns an empty string when `type` is not an enum, `valueAddress` is null, or no
// case matches.
#[ConstExpr]
func enumName(type: typeinfo?, valueAddress: const *void?, fullyQualified = true)->String
{
    var result: retval
    if not isEnum(type) or not valueAddress do
        return result
    let safeType  = type!
    let safeValue = valueAddress
    let typeEnum  = cast #assume(const *TypeInfoEnum) safeType
    let rawType   = typeEnum.rawType!
    let isFlags   = hasAttribute(type, EnumFlags)

    // Get the user value, as an 'u64' or a string
    var val1:  u64
    var val1s: string?
    switch rawType.sizeof
    {
    case 1:  val1 = cast(u64) (cast(const *u8) safeValue)[]
    case 2:  val1 = cast(u64) (cast(const *u16) safeValue)[]
    case 4:  val1 = cast(u64) (cast(const *u32) safeValue)[]
    case 8:  val1 = cast(u64) (cast(const *u64) safeValue)[]
    case 16: val1s = (cast(const *(string?)) safeValue)[]
    default: return result
    }

    let simpleName = safeType.name
    var covered    = 0'u64

    for it in typeEnum.values
    {
        if not it.value do
            continue
        let safeItValue = it.value

        // Get the enum value, as an 'u64' or a string
        var val2:  u64
        var val2s: string?
        switch rawType.sizeof
        {
        case 1:  val2 = cast(u64) (cast(const *u8) safeItValue)[]
        case 2:  val2 = cast(u64) (cast(const *u16) safeItValue)[]
        case 4:  val2 = cast(u64) (cast(const *u32) safeItValue)[]
        case 8:  val2 = cast(u64) (cast(const *u64) safeItValue)[]
        case 16: val2s = (cast(const *(string?)) safeItValue)[]
        }

        // For a normal enum, stop if this is a match
        if not isFlags and val1 == val2 and val1s == val2s
        {
            if fullyQualified
            {
                result += simpleName
                result += "."
            }

            result += it.name
            return result
        }

        // For a flags enum, name a case whose bits are all set and not yet covered by earlier names.
        let zeroMatch = val1 == 0 and val2 == 0 and result.isEmpty()
        let bitsMatch = val2 != 0 and (val1 & val2) == val2 and (val2 & ~covered) != 0
        if isFlags and (zeroMatch or bitsMatch)
        {
            covered |= val2
            if not result.isEmpty() do
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
