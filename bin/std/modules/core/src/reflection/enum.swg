#global public
#global namespace Reflection

using Swag

// Returns an enum's underlying native type, or the input type when it is not an enum.
#[ConstExpr]
func enumUnderlyingType(type: typeinfo)->typeinfo
{
    if not isEnum(type) do
        return type

    let enumType = assume cast(const *TypeInfoEnum, type)
    return enumType.rawType!
}

// Returns reflected information for a named enum value, or null.
#[ConstExpr]
func enumValue(type: typeinfo?, name: string?)->const *TypeValue?
{
    if not isEnum(type) do
        return null

    let typeEnum = assume cast(const *TypeInfoEnum, type)
    for &caseInfo in typeEnum.values where caseInfo.name == name do
        return caseInfo
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
    let enumTypeInfo      = type!
    let inputValueAddress = valueAddress
    let typeEnum          = assume cast(const *TypeInfoEnum, enumTypeInfo)
    let rawType           = typeEnum.rawType!
    let isFlags           = hasAttribute(type, EnumFlags)

    // Read the input using the enum's underlying representation.
    var inputBits: u64
    var inputText: string?
    switch rawType.sizeof
    {
    case 1:  inputBits = cast(u64, cast(const *u8, inputValueAddress)[])
    case 2:  inputBits = cast(u64, cast(const *u16, inputValueAddress)[])
    case 4:  inputBits = cast(u64, cast(const *u32, inputValueAddress)[])
    case 8:  inputBits = cast(u64, cast(const *u64, inputValueAddress)[])
    case 16: inputText = cast(const *(string?), inputValueAddress)[]
    default: return result
    }

    let simpleName  = enumTypeInfo.name
    var coveredBits = 0'u64

    for caseInfo in typeEnum.values
    {
        if not caseInfo.value do
            continue
        let caseValueAddress = caseInfo.value

        // Read this case using the same representation.
        var caseBits: u64
        var caseText: string?
        switch rawType.sizeof
        {
        case 1:  caseBits = cast(u64, cast(const *u8, caseValueAddress)[])
        case 2:  caseBits = cast(u64, cast(const *u16, caseValueAddress)[])
        case 4:  caseBits = cast(u64, cast(const *u32, caseValueAddress)[])
        case 8:  caseBits = cast(u64, cast(const *u64, caseValueAddress)[])
        case 16: caseText = cast(const *(string?), caseValueAddress)[]
        }

        // For a normal enum, stop if this is a match
        if not isFlags and inputBits == caseBits and inputText == caseText
        {
            if fullyQualified
            {
                result += simpleName
                result += "."
            }

            result += caseInfo.name
            return result
        }

        // For a flags enum, name a case whose bits are all set and not yet covered by earlier names.
        let zeroMatch = inputBits == 0 and caseBits == 0 and result.isEmpty()
        let bitsMatch = caseBits != 0 and (inputBits & caseBits) == caseBits and (caseBits & ~coveredBits) != 0
        if isFlags and (zeroMatch or bitsMatch)
        {
            coveredBits |= caseBits
            if not result.isEmpty() do
                result += " | "

            if fullyQualified
            {
                result += simpleName
                result += "."
            }

            result += caseInfo.name
        }
    }

    return result
}
