#global public
#global namespace StrConv

using Swag, Globalization

// Represents convert format.
struct ConvertFormat
{
    public
    {
        formatInt:   ConvertFormatInt       // Format int associated with this value.
        formatFloat: ConvertFormatFloat     // Format float associated with this value.
    }
}

// Format structure to convert a float to a string
struct ConvertFormatFloat
{
    public
    {
        precision: s8 = -1        // -1 is for 'most possible precision'
        fmt:       u8 = 'f'u8     // Fmt associated with this value.
        forceSign: bool           // Force sign associated with this value.
    }
}

impl ConvertFormatFloat
{
    // Set some format options with a given user string.
    // Format is `[+][fmt][precision]`
    //
    // + '+'
    //     To force the positive sign if the number is positive
    // + 'fmt'
    //     This is the output format:
    //     | e | -d.dddde±dd, a decimal exponent
    //     | E | -d.ddddE±dd, a decimal exponent
    //     | f | -ddd.dddd, no exponent
    //     | g | 'e' for large exponents, 'f' otherwise
    //     | G | 'E' for large exponents, 'f' otherwise
    // + 'precision'
    //     A number which is the precision of the fractional part
    mtd setFormat(strFormat: string?)
    {
        let buffer  = strFormat.buffer
        let countof = strFormat.count
        if buffer == null or countof == 0 do
            return

        var cpt = 0'u32

        // Force sign for positive numbers
        if buffer[cpt] == '+'u8
        {
            .forceSign = true
            cpt        += 1
        }

        // Format
        if cpt < countof
        {
            switch buffer[cpt]
            {
            case 'e'u8, 'E'u8, 'f'u8, 'g'u8, 'G'u8:
                .fmt = buffer[cpt]
                cpt  += 1
            }
        }

        // Precision
        if cpt < countof
        {
            let {userWidth, eatCount, ?} = expect parseU64(Swag.makeString(buffer + cpt, cast(u64) (countof - cpt)))
            Debug.assert(userWidth <= 255, "precision overflow")
            if eatCount do
                .precision = cast(s8) userWidth
        }
    }
}

// Format structure to convert an integer to a string
//
// If 'signed' is 'true', the value to convert must be stored in 'signedValue', otherwise it must
// be stored in 'unsignedValue'.
struct ConvertFormatInt
{
    public
    {
        base:      u32 = 10     // Base associated with this value.
        padding:   u8           // Padding associated with this value.
        width:     u8           // Width in logical units.
        forceSign: bool         // Force sign associated with this value.
    }
}

impl ConvertFormatInt
{
    // Set some format options with a given user string.
    // The format is `[+][fmt][padding][width]'
    //
    // + `+'
    //     To force the positive sign if the number is positive
    // + 'fmt'
    //     This is the output format:
    //     | B | Binary
    //     | D | Decimal
    //     | X | Hexadecimal
    // + 'padding'
    //     The padding character, in ascii. It's mandatory before the next field
    // + 'width'
    //     The width of the output, in number of characters
    mtd setFormat(strFormat: string?)
    {
        let buffer  = strFormat.buffer
        let countof = strFormat.count
        if buffer == null or countof == 0 do
            return

        var cpt = 0'u32

        // Force sign for positive numbers
        if buffer[cpt] == '+'u8
        {
            .forceSign = true
            cpt        += 1
        }

        // Base
        switch buffer[cpt]
        {
        case 'B'u8:
            .base = 2
            cpt   += 1

        case 'D'u8:
            .base = 10
            cpt   += 1

        case 'X'u8:
            .base = 16
            cpt   += 1
        }

        // Next comes the padding characters
        if cpt >= countof do
            return
        .padding = buffer[cpt]
        cpt      += 1

        // Next comes the padding width
        if cpt >= countof do
            return
        let {userWidth, eatCount, ?} = expect parseU64(Swag.makeString(buffer + cpt, cast(u64) countof - cpt))
        Debug.assert(userWidth <= 255, "padding width overflow")
        if eatCount do
            .width = cast(u8) userWidth
    }
}

// Convert a value to an utf8 string, and append the result in a ConcatBuffer
func convertAny(buf: *ConcatBuffer, value: const any?, convFmt: ConvertFormat, strFormat: string?)
{
    var valueData = value.buffer
    var type      = Reflection.resolveAliases(Swag.kindOf(value))

    // A reference
    if Reflection.isPointerRef(type)
    {
        let ptrType = cast(const *TypeInfoPointer) type!
        valueData = valueData![as *void]
        type      = ptrType.pointedType!
    }

    let concreteValue = Swag.makeAny(valueData, type)

    // This is a type
    if Reflection.isType(type)
    {
        let ptrType = valueData![as typeinfo?]
        if ptrType do
            buf.addBytes(ptrType.fullname)
        else do
            buf.addBytes("null")
        return
    }

    // A pointer, whatever type
    if Reflection.isPointer(type)
    {
        if type.flags & TypeInfoFlags.CString
        {
            let ptr = valueData![as [*] u8]
            let len = (cast(cstring?) ptr).count
            buf.addBytes(Swag.makeSlice(ptr, len))
            return
        }

        var fmt: ConvertFormatInt
        fmt.base    = 16
        fmt.width   = 16
        fmt.padding = '0'u8
        fmt.setFormat(strFormat)
        convertInt(buf, valueData![as u64], fmt)
        return
    }

    // An enum value
    if Reflection.isEnum(type)
    {
        let enumName = Reflection.enumName(type, valueData)
        if !enumName.isEmpty() do
            buf.addBytes(Swag.makeSlice(enumName.buffer, cast(u64) enumName.length))
        else do
            buf.addBytes("?")
        return
    }

    // A struct
    if Reflection.isStruct(type)
    {
        convertStruct(buf, concreteValue, convFmt, strFormat)
        return
    }

    // A slice
    if Reflection.isSlice(type)
    {
        let ptrSlice = cast(const *TypeInfoSlice) type!
        buf.addBytes("[")

        let sl       = cast(const [..] u8?) valueData
        var bufSlice = sl.buffer
        for index in sl.count
        {
            if index do
                buf.addBytes(", ")
            let v = Swag.makeAny(bufSlice, ptrSlice.pointedType)
            convertAny(buf, v, convFmt, strFormat)
            bufSlice += ptrSlice.pointedType!.sizeof
        }

        buf.addBytes("]")
        return
    }

    // A static array
    if Reflection.isStaticArray(type)
    {
        let ptrArr = cast(const *TypeInfoArray) type!
        var bufArr = cast(const [*] u8?) valueData

        buf.addBytes("[")
        for index in ptrArr.count
        {
            if index do
                buf.addBytes(", ")
            let v = Swag.makeAny(bufArr, ptrArr.pointedType)
            convertAny(buf, v, convFmt, strFormat)
            bufArr += ptrArr.pointedType!.sizeof
        }

        buf.addBytes("]")
        return
    }

    if Reflection.isInteger(type)
    {
        convertIntAny(buf, concreteValue, convFmt, strFormat)
        return
    }

    if Reflection.isFloat(type)
    {
        convertFloatAny(buf, concreteValue, convFmt, strFormat)
        return
    }

    // Any
    if Reflection.isAny(type)
    {
        let ptrAny = cast(const * (any?)) valueData!
        buf.addBytes("{type = ")
        let typeAny = Swag.kindOf(ptrAny[])
        convertAny(buf, typeAny, convFmt, strFormat)
        buf.addBytes(", value = ")
        if (ptrAny[]).buffer do
            convertAny(buf, ptrAny[]!, convFmt, strFormat)
        else do
            buf.addBytes("null")
        buf.addBytes("}")
        return
    }

    // `const any` keeps qualifiers on native payload types, so exact typeinfo
    // matching is too strict here. Switch on the native kind instead.
    if Reflection.isNative(type)
    {
        let typeNative = cast(const *TypeInfoNative) type!
        switch typeNative.nativeKind
        {
        case .Bool:
            convertBool(buf, valueData![as bool])
            return

        case .Rune:
            convertRune(buf, valueData![as rune])
            return

        case .String:
            buf.addBytes(valueData![as string])
            return
        }
    }

    buf.addBytes("?")
}

// Convert a structure content to an utf8 string, and put the result in a ConcatBuffer
func convertStruct(buf: *ConcatBuffer, value: const any?, convFmt: ConvertFormat, strFormat: string?)
{
    let kindof = cast(const *Swag.TypeInfoStruct) Swag.kindOf(value)!
    Debug.assert(kindof.kind == TypeInfoKind.Struct, "this is not a structure")
    let ptr = cast(const [*] u8?) value.buffer

    // Core.String
    if kindof == String
    {
        let ptrStr = cast(const *String) ptr!
        buf.addBytes(Swag.makeSlice(ptrStr.buffer, ptrStr.length))
        return
    }

    // A structure with an implementation of IConvert
    let itf = Swag.makeInterface(ptr, kindof, IConvert)
    if itf != null
    {
        itf.convert(buf, convFmt, strFormat)
        return
    }

    // Do it field by field
    buf.addBytes("{")
    for field, index in kindof.fields
    {
        if index do
            buf.addBytes(", ")
        buf.addBytes(field.name)
        buf.addBytes(" = ")
        let val = Swag.makeAny(ptr + field.offset, field.pointedType)
        convertAny(buf, val, convFmt, strFormat)
    }

    buf.addBytes("}")
}

// Convert a float to an utf8 string, and put the result in a ConcatBuffer
func convertFloat(buf: *ConcatBuffer, value: const any?, fmt: ConvertFormatFloat)
{
    let kindof = cast(const *Swag.TypeInfoNative) Swag.kindOf(value)!
    Debug.assert(kindof.flags & TypeInfoFlags.Float != 0, "value to convert is not a float")

    let dataof = value.buffer

    var value64: f64
    switch kindof.nativeKind
    {
    case .F32: value64 = cast(f64) dataof![as f32]
    case .F64: value64 = dataof![as f64]
    }

    Dtoa.parse(buf, value64, fmt.fmt, cast(s64) fmt.precision, fmt.forceSign)
}

// Convert an integer to an utf8 string, and put the result in a ConcatBuffer
func convertInt(buf: *ConcatBuffer, value: const any?, fmt: ConvertFormatInt)
{
    let kindof = cast(const *Swag.TypeInfoNative) Swag.kindOf(value)!
    Debug.assert(kindof.flags & TypeInfoFlags.Integer != 0, "value to convert is not an integer")
    Debug.assert(0 < fmt.base and fmt.base <= 16, "invalid convert base")

    let dataof = value.buffer
    var bits   = kindof.sizeof * 8

    var value64:     u64
    var signedValue: s64

    var overflowS64 = false
    switch kindof.nativeKind
    {
    case .S8:
        signedValue = cast(s64) dataof![as s8]
        value64     = cast(u64) Math.abs(signedValue)

    case .S16:
        signedValue = cast(s64) dataof![as s16]
        value64     = cast(u64) Math.abs(signedValue)

    case .S32:
        signedValue = cast(s64) dataof![as s32]
        value64     = cast(u64) Math.abs(signedValue)

    case .S64:
        signedValue = dataof![as s64]
        if signedValue == Swag.S64.Min do
            overflowS64 = true
        else do
            value64 = cast(u64) Math.abs(signedValue)

    case .U8:
        value64 = cast(u64) dataof![as u8]

    case .U16:
        value64 = cast(u64) dataof![as u16]

    case .U32:
        value64 = cast(u64) dataof![as u32]

    case .U64:
        value64 = dataof![as u64]
    }

    const Tbl = "0123456789ABCDEF"
    var tmp: [64] u8
    var cpt = 63'u32

    // Special case for the lower digit of Swag.S64.Min
    // We have 9_223_372_036_854_775_807, and we want -9_223_372_036_854_775_808
    // So use '8' instead of '7'
    if overflowS64
    {
        let c = Tbl[8 % fmt.base]
        tmp[cpt]  = c
        cpt, bits -= 1
        switch fmt.base
        {
        case 2:  value64 = 4611686018427387904
        case 10: value64 = 922337203685477580
        case 16: value64 = 576460752303423488
        }
    }

    for bits
    {
        let c = Tbl[value64 % fmt.base]
        tmp[cpt] = c
        cpt      -= 1
        value64  /= cast(u64) fmt.base
        if !value64 do
            break
    }

    // Fill the remaining place with the padding character, so that the total result,
    // including an eventual sign, is 'fmt.width' long.
    if fmt.padding
    {
        let signWidth = signedValue < 0 or fmt.forceSign ? 1'u32 : 0'u32
        var curWidth  = 63 - cpt
        while curWidth < fmt.width and cpt > 1
        {
            if curWidth + signWidth >= fmt.width do
                break
            tmp[cpt] = fmt.padding
            curWidth += 1
            cpt      -= 1
        }
    }

    // Prepend the negative character
    if signedValue < 0
    {
        tmp[cpt] = cast(u8) g_CultureInfo.numberFormat.negativeSign
        cpt      -= 1
    }
    elif fmt.forceSign
    {
        tmp[cpt] = cast(u8) g_CultureInfo.numberFormat.positiveSign
        cpt      -= 1
    }

    buf.addBytes(cast([..] u8) Swag.makeSlice(&tmp[cpt + 1], cast(u64) 63 - cpt))
}

// Convert a float to an utf8 string, and put the result in a ConcatBuffer
func convertFloatAny(buf: *ConcatBuffer, value: const any?, convFmt: ConvertFormat, strFormat: string?)
{
    Debug.assert(Swag.kindOf(value).flags & TypeInfoFlags.Float != 0, "value to convert is not a float")

    var fmt = convFmt.formatFloat
    fmt.setFormat(strFormat)
    convertFloat(buf, value, fmt)
}

// Convert an integer to an utf8 string, and put the result in a ConcatBuffer
func convertIntAny(buf: *ConcatBuffer, value: const any?, convFmt: ConvertFormat, strFormat: string?)
{
    Debug.assert(Swag.kindOf(value).flags & TypeInfoFlags.Integer != 0, "value to convert is not an integer")

    var fmt = convFmt.formatInt
    fmt.setFormat(strFormat)
    convertInt(buf, value, fmt)
}

// Convert a 'bool' to a string, and put the result in a ConcatBuffer
func convertBool(buf: *ConcatBuffer, value: bool)
{
    buf.addBytes(value ? "true" : "false")
}

// Convert a 'rune' to a string, and put the result in a ConcatBuffer
func convertRune(buf: *ConcatBuffer, value: rune)
{
    var arr: [4] u8
    if !value do
        buf.addBytes("?")
    else
    {
        let count = Utf8.encodeRune(arr, value)
        buf.addBytes(Swag.makeSlice(&arr[0], cast(u64) count))
    }
}

// Templated version. Convert a value of type 'T'
func(T) convert(buf: *ConcatBuffer, value: T, convFmt: ConvertFormat, strFormat: string?)
{
    #static if Reflection.isInteger(T)
    {
        var fmt: ConvertFormatInt
        fmt.setFormat(strFormat)
        convertInt(buf, value, fmt)
    }
    elif Reflection.isFloat(T)
    {
        var fmt: ConvertFormatFloat
        fmt.setFormat(strFormat)
        convertFloat(buf, value, fmt)
    }
    elif Reflection.isBool(T)
    {
        convertBool(buf, value)
    }
    elif Reflection.isRune(T)
    {
        convertRune(buf, value)
    }
    elif Reflection.isString(T)
    {
        buf.addBytes(value)
    }
    else
    {
        convertAny(buf, value, convFmt, strFormat)
    }
}
