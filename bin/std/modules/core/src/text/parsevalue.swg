#global namespace StrConv

using Swag, Core.Errors

// This function will parse the string 'buf' and decode the corresponding value in 'addr'.
// 'addr' must point to an initialized memory location that can hold 'type'
//
// Accepted types are :
// - `s8, s16, s32, s64, u8, u16, u32, u64, rune, bool, f32, f64`
// - 'Core.String'  literal strings are not supported as 'buf' is supposed to be transient
// - enum           with or without 'Swag.EnumFlags' attribute
// - struct         a brace-enclosed list of field values in declaration order, such as
//                  `{{1 29 27 27} 0}`; a `}` before the last field leaves the remaining
//                  fields untouched, and `,` between two values is accepted
//
// 'buf' can contain multiple values separated with blanks if 'type' is:
// - a static array of the types above
// - a dynamic 'Core.Array' of the types above
public func parseValue(addr: *void, type: typeinfo, buf: string)->#null string fail
{
    var patch = cast(*u8) addr
    var one   = Tokenize.eatSpaces(buf)

    // Dynamic Core.Array
    let valueType = Reflection.dynamicArrayElementType(type)
    if valueType
    {
        let safeValueType = valueType
        while one.count and one[0] != '#'
        {
            let addrVal = Reflection.appendDynamicArrayElement(addr, safeValueType)
            one = (parseValue(addrVal!, safeValueType, one) orelse "")
            one = Tokenize.eatSpaces(one)
        }

        return one
    }

    // Static array
    if Reflection.isStaticArray(type)
    {
        let arrayType = cast(const *TypeInfoArray) type
        var addrVal   = cast([*] u8) addr
        var cpt       = 0
        while one.count and one[0] != '#'
        {
            if cpt == arrayType.totalCount do
                fail InvalidFormatError{"too many static array values"}
            one     = (parseValue(addrVal, arrayType.finalType, one) orelse "")
            one     = Tokenize.eatSpaces(one)
            addrVal += arrayType.finalType.sizeof
            cpt     += 1
        }

        return one
    }

    // Enum
    if Reflection.isEnum(type)
    {
        let enumType = cast(const *TypeInfoEnum) type
        let rawType  = enumType.rawType!
        if rawType != string and enumType.sizeof > 8 do
            fail UnsupportedFormatError{Errors.mkString(Format.toString("unsupported enum type [[%]]", rawType.name))}
        let enumFlags = Reflection.hasAttribute(enumType, EnumFlags)

        for
        {
            one = Tokenize.eatSpaces(one)
            let id = parseIdentifier(one) orelse ""
            let v  = Reflection.enumValue(type, id)
            if !v do
                fail InvalidFormatError{Errors.mkString(Format.toString("unknown enum value [[%]]", id))}
            let enumValue = v.value!

            if enumType.rawType == string
            {
                patch[as string] = enumValue[as string]
            }
            elif !enumFlags
            {
                switch enumType.sizeof
                {
                case 1: patch[as u8] = enumValue[as u8]
                case 2: patch[as u16] = enumValue[as u16]
                case 4: patch[as u32] = enumValue[as u32]
                case 8: patch[as u64] = enumValue[as u64]
                }
            }
            else
            {
                switch enumType.sizeof
                {
                case 1: patch[as u8] |= enumValue[as u8]
                case 2: patch[as u16] |= enumValue[as u16]
                case 4: patch[as u32] |= enumValue[as u32]
                case 8: patch[as u64] |= enumValue[as u64]
                }
            }

            one = Tokenize.eatCount(one, id.count)
            if !enumFlags do
                break

            one = Tokenize.eatSpaces(one)
            if !one.count do
                break
            if one[0] == '#' do
                break

            if one[0] != '|' do
                fail InvalidFormatError{"invalid enum flags format"}
            one = Tokenize.eatCount(one, 1)
        }

        let eat = cast(u32) cast(s64) (one.buffer - buf.buffer)
        one = Tokenize.eatCount(buf, cast(u64) eat)
        return one
    }

    // Decode interface
    if let itf = Swag.makeInterface(addr, type, IPokeValue) do
        return itf.poke(one)

    // Struct: a brace-enclosed list of field values in declaration order. 'Core.String' is
    // excluded because it decodes as a quoted literal below, and a type with a poke interface
    // was already given the whole text above.
    if Reflection.isStruct(type) and type != String
    {
        let structType = cast(const *TypeInfoStruct) type
        if !one.count or one[0] != '{' do
            fail InvalidFormatError{Errors.mkString(Format.toString("missing [[{]] for struct [[%]]", type.name))}
        one = Tokenize.eatCount(one, 1)
        one = Tokenize.eatSpaces(one)

        for field in structType.fields
        {
            if !one.count or one[0] == '}' do
                break
            one = (parseValue(cast([*] u8) addr + field.offset, field.pointedType!, one) orelse "")
            one = Tokenize.eatSpaces(one)
            if one.count and one[0] == ','
            {
                one = Tokenize.eatCount(one, 1)
                one = Tokenize.eatSpaces(one)
            }
        }

        if !one.count or one[0] != '}' do
            fail InvalidFormatError{Errors.mkString(Format.toString("missing [[}]] for struct [[%]]", type.name))}
        one = Tokenize.eatCount(one, 1)
        return one
    }

    // Basic types. A native type reaching this function from another module is a
    // different typeinfo instance, so the dispatch reads the native kind instead of
    // switching on typeinfo identity.
    var eat = 0'u32
    var ovf = false
    if type == String
    {
        eat = parseString(cast(*String) patch, one)
        return Tokenize.eatCount(one, cast(u64) eat)
    }

    if !Reflection.isNative(type) do
        fail UnsupportedFormatError{Errors.mkString(Format.toString("unsupported type [[%]]", type.name))}

    let nativeType = cast(const *TypeInfoNative) type
    switch nativeType.nativeKind
    {
    case .S8:
        var val: s8 = undefined
        {val, eat, ovf} = parseS8(one)
        if ovf do
            fail OverflowError{}
        patch[as s8] = val

    case .S16:
        var val: s16 = undefined
        {val, eat, ovf} = parseS16(one)
        if ovf do
            fail OverflowError{}
        patch[as s16] = val

    case .S32:
        var val: s32 = undefined
        {val, eat, ovf} = parseS32(one)
        if ovf do
            fail OverflowError{}
        patch[as s32] = val

    case .S64:
        var val: s64 = undefined
        {val, eat, ovf} = parseS64(one)
        if ovf do
            fail OverflowError{}
        patch[as s64] = val

    case .U8:
        var val: u8 = undefined
        {val, eat, ovf} = parseU8(one)
        if ovf do
            fail OverflowError{}
        patch[as u8] = val

    case .U16:
        var val: u16 = undefined
        {val, eat, ovf} = parseU16(one)
        if ovf do
            fail OverflowError{}
        patch[as u16] = val

    case .U32:
        var val: u32 = undefined
        {val, eat, ovf} = parseU32(one)
        if ovf do
            fail OverflowError{}
        patch[as u32] = val

    case .U64:
        var val: u64 = undefined
        {val, eat, ovf} = parseU64(one)
        if ovf do
            fail OverflowError{}
        patch[as u64] = val

    case .F32:
        var val: f32 = undefined
        {val, eat, ovf} = parseF32(one)
        if ovf do
            fail OverflowError{}
        patch[as f32] = val

    case .F64:
        var val: f64 = undefined
        {val, eat, ovf} = parseF64(one)
        if ovf do
            fail OverflowError{}
        patch[as f64] = val

    case .Bool:
        var val: bool = undefined
        {val, eat}     = parseBool(one)
        patch[as bool] = val

    case .Rune:
        var val: rune = undefined
        {val, eat}     = parseRune(one)
        patch[as rune] = val

    default:
        fail UnsupportedFormatError{Errors.mkString(Format.toString("unsupported type [[%]]", type.name))}
    }

    return Tokenize.eatCount(one, cast(u64) eat)
}
