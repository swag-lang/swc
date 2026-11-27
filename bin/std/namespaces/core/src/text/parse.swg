#global public
#global namespace StrConv

using Globalization, Swag, Errors

// Parses the hexadecimal digits at the start of `str` as an unsigned integer.
//
// Returns the value, the number of bytes consumed in `eat`, and `ovf` set when the value does not
// fit in a `u64`; the remaining digits are consumed all the same. Fails with
// [[Core.Errors.SyntaxError]] when `str` does not start with a hexadecimal digit.
func parseX64(str: string)->{ value: u64, eat: u32, ovf: bool } fail
{
    var result: #returntype

    let byteCount = str.count
    if not byteCount
    {
        fail SyntaxError{}
    }

    var buffer        = str.buffer
    var consumedBytes = 0_u32
    var value         = 0_u64

    if not Latin1.isHexDigit(buffer[])
    {
        fail SyntaxError{}
    }

    while consumedBytes < byteCount and Latin1.isHexDigit(buffer[])
    {
        if consumedBytes == Swag.U32.Max
        {
            fail OverflowError{"numeric token exceeds the supported length"}
        }

        if value & 0xF0000000_00000000
        {
            result.ovf = true
        }
        else
        {
            value <<= 4
            let character = buffer[]
            if Latin1.isDigit(character)
            {
                value += cast(u64, (character - '0'_u8))
            }
            else if character <= 'F'_u8
            {
                value += 10_u64 + (character - 'A'_u8)
            }
            else
            {
                value += 10_u64 + (character - 'a'_u8)
            }
        }

        buffer, consumedBytes += 1
    }

    result.value = value
    result.eat   = consumedBytes
    return result
}

// Parses the binary digits at the start of `str` as an unsigned integer.
//
// Returns the value, the number of bytes consumed in `eat`, and `ovf` set when the value does not
// fit in a `u64`; the remaining digits are consumed all the same. Fails with
// [[Core.Errors.SyntaxError]] when `str` does not start with '0' or '1'.
func parseB64(str: string)->{ value: u64, eat: u32, ovf: bool } fail
{
    var result: #returntype

    let byteCount = str.count
    if not byteCount
    {
        fail SyntaxError{}
    }

    var buffer        = str.buffer
    var consumedBytes = 0_u32
    var value         = 0_u64

    if not Latin1.isBinDigit(buffer[])
    {
        fail SyntaxError{}
    }

    while consumedBytes < byteCount and Latin1.isBinDigit(buffer[])
    {
        if consumedBytes == Swag.U32.Max
        {
            fail OverflowError{"numeric token exceeds the supported length"}
        }

        if value & 0x80000000_00000000
        {
            result.ovf = true
        }
        else
        {
            value <<= 1
            value += cast(u64, (buffer[] - '0'_u8))
        }

        buffer, consumedBytes += 1
    }

    result.value = value
    result.eat   = consumedBytes
    return result
}

// Parses the unsigned integer at the start of `str` as a `u8`, like [[Core.StrConv.parseU64]].
//
// A value above `Swag.U8.Max` saturates to it and sets `ovf`.
func parseU8(str: string)->{ value: u8, eat: u32, ovf: bool } fail
{
    let {value, eat, ovf} = try parseU64(str)
    if value > Swag.U8.Max
    {
        return {value: Swag.U8.Max, eat: eat, ovf: true}
    }

    return {value: cast(u8, value), eat: eat, ovf: ovf}
}

// Parses the unsigned integer at the start of `str` as a `u16`, like [[Core.StrConv.parseU64]].
//
// A value above `Swag.U16.Max` saturates to it and sets `ovf`.
func parseU16(str: string)->{ value: u16, eat: u32, ovf: bool } fail
{
    let {value, eat, ovf} = try parseU64(str)
    if value > Swag.U16.Max
    {
        return {value: Swag.U16.Max, eat: eat, ovf: true}
    }

    return {value: cast(u16, value), eat: eat, ovf: ovf}
}

// Parses the unsigned integer at the start of `str` as a `u32`, like [[Core.StrConv.parseU64]].
//
// A value above `Swag.U32.Max` saturates to it and sets `ovf`.
func parseU32(str: string)->{ value: u32, eat: u32, ovf: bool } fail
{
    let {value, eat, ovf} = try parseU64(str)
    if value > Swag.U32.Max
    {
        return {value: Swag.U32.Max, eat: eat, ovf: true}
    }

    return {value: cast(u32, value), eat: eat, ovf: ovf}
}

// Parses the unsigned integer at the start of `str`.
//
// Accepts decimal digits, or a `0x` or `0b` prefix followed by hexadecimal or binary digits.
// Returns the value, the number of bytes consumed in `eat`, and `ovf` set when the value does not
// fit in a `u64`. Fails with [[Core.Errors.SyntaxError]] when `str` does not start with a digit.
func parseU64(str: string)->{ value: u64, eat: u32, ovf: bool } fail
{
    var result: #returntype

    let byteCount = str.count
    if not byteCount
    {
        fail SyntaxError{}
    }

    // Detect 0x for hexadecimal, 0b for binary.
    if byteCount >= 2 and str[0] == '0'_u8
    {
        let prefix = str[1] | 32
        if prefix == 'x'_u8
        {
            {value: result.value, eat: result.eat, ovf: result.ovf} = try parseX64(str[2 to])
            if result.eat > Swag.U32.Max - 2
            {
                fail OverflowError{"numeric token exceeds the supported length"}
            }

            result.eat += 2
            return result
        }

        if prefix == 'b'_u8
        {
            {value: result.value, eat: result.eat, ovf: result.ovf} = try parseB64(str[2 to])
            if result.eat > Swag.U32.Max - 2
            {
                fail OverflowError{"numeric token exceeds the supported length"}
            }

            result.eat += 2
            return result
        }
    }

    var buffer        = str.buffer
    var consumedBytes = 0_u32
    var value         = 0_u64
    let maxValue      = Swag.U64.Max
    let maxQuotient   = maxValue / 10
    let maxRemainder  = maxValue % 10

    if not Latin1.isDigit(buffer[])
    {
        fail SyntaxError{}
    }

    while consumedBytes < byteCount and Latin1.isDigit(buffer[])
    {
        if consumedBytes == Swag.U32.Max
        {
            fail OverflowError{"numeric token exceeds the supported length"}
        }

        let digit = cast(u64, (buffer[] - '0'_u8))
        if value > maxQuotient or (value == maxQuotient and digit > maxRemainder)
        {
            result.ovf = true
            value      = maxValue
        }
        else
        {
            value = value * 10 + digit
        }

        buffer, consumedBytes += 1
    }

    result.value = value
    result.eat   = consumedBytes
    return result
}

// Parses the signed decimal integer at the start of `str` as an `s8`, like [[Core.StrConv.parseS64]].
//
// A value outside the `s8` range saturates to the nearest bound and sets `ovf`.
func parseS8(str: string)->{ value: s8, eat: u32, ovf: bool } fail
{
    let {value, eat, ovf} = try parseS64(str)
    if value < Swag.S8.Min
    {
        return {value: Swag.S8.Min, eat: eat, ovf: true}
    }

    if value > Swag.S8.Max
    {
        return {value: Swag.S8.Max, eat: eat, ovf: true}
    }

    return {value: cast(s8, value), eat: eat, ovf: ovf}
}

// Parses the signed decimal integer at the start of `str` as an `s16`, like [[Core.StrConv.parseS64]].
//
// A value outside the `s16` range saturates to the nearest bound and sets `ovf`.
func parseS16(str: string)->{ value: s16, eat: u32, ovf: bool } fail
{
    let {value, eat, ovf} = try parseS64(str)
    if value < Swag.S16.Min
    {
        return {value: Swag.S16.Min, eat: eat, ovf: true}
    }

    if value > Swag.S16.Max
    {
        return {value: Swag.S16.Max, eat: eat, ovf: true}
    }

    return {value: cast(s16, value), eat: eat, ovf: ovf}
}

// Parses the signed decimal integer at the start of `str` as an `s32`, like [[Core.StrConv.parseS64]].
//
// A value outside the `s32` range saturates to the nearest bound and sets `ovf`.
func parseS32(str: string)->{ value: s32, eat: u32, ovf: bool } fail
{
    let {value, eat, ovf} = try parseS64(str)
    if value < Swag.S32.Min
    {
        return {value: Swag.S32.Min, eat: eat, ovf: true}
    }

    if value > Swag.S32.Max
    {
        return {value: Swag.S32.Max, eat: eat, ovf: true}
    }

    return {value: cast(s32, value), eat: eat, ovf: ovf}
}

// Parses the signed decimal integer at the start of `str`.
//
// An optional leading sign is spelled as in the current culture's number format. Returns the
// value, the number of bytes consumed in `eat`, and `ovf` set when the value does not fit in an
// `s64`; on overflow, `value` saturates to the signed bound. Fails with
// [[Core.Errors.ParseIncompleteError]] when `str` holds only a sign, and with
// [[Core.Errors.SyntaxError]] when no digit follows.
func parseS64(str: string)->{ value: s64, eat: u32, ovf: bool } fail
{
    var result: #returntype

    let byteCount = str.count
    if not byteCount
    {
        fail SyntaxError{}
    }

    var buffer        = str.buffer
    var value         = 0_u64
    var consumedBytes = 0_u32

    // An optional sign comes first.
    var negative      = false
    let signCharacter = str[0]
    var maxValue      = cast(u64, Swag.S64.Max)
    if signCharacter == g_CultureInfo.numberFormat.negativeSign
    {
        buffer, consumedBytes += 1
        negative = true
        maxValue += 1
        if consumedBytes == byteCount
        {
            fail ParseIncompleteError{}
        }
    }
    else if signCharacter == g_CultureInfo.numberFormat.positiveSign
    {
        buffer, consumedBytes += 1
        if consumedBytes == byteCount
        {
            fail ParseIncompleteError{}
        }
    }

    // Accumulate the magnitude, continuing through overflowing digits.
    if not Latin1.isDigit(buffer[])
    {
        fail SyntaxError{}
    }

    let maxQuotient  = maxValue / 10
    let maxRemainder = maxValue % 10
    while consumedBytes < byteCount and Latin1.isDigit(buffer[])
    {
        if consumedBytes == Swag.U32.Max
        {
            fail OverflowError{"numeric token exceeds the supported length"}
        }

        let digit = cast(u64, (buffer[] - '0'_u8))
        if value > maxQuotient or (value == maxQuotient and digit > maxRemainder)
        {
            result.ovf = true
            value      = Swag.U64.Max
        }
        else
        {
            value = value * 10 + digit
        }

        buffer, consumedBytes += 1
    }

    if not result.ovf
    {
        if negative
        {
            if value == maxValue
            {
                result.value = Swag.S64.Min
            }
            else
            {
                result.value = -cast(s64, value)
            }
        }
        else
        {
            result.value = cast(s64, value)
        }
    }
    else if negative
    {
        result.value = Swag.S64.Min
    }
    else
    {
        result.value = Swag.S64.Max
    }

    result.eat = consumedBytes
    return result
}

// Parses the floating-point number at the start of `str` as an `f32`, like [[Core.StrConv.parseF64]].
//
// A magnitude below `Swag.F32.MinNormal` is kept as the subnormal value it rounds to, or as zero, the way
// [[Core.StrConv.parseF64]] treats an `f64`: every `f32` written with enough digits reads back
// unchanged. A magnitude above `Swag.F32.Max` saturates to that bound and sets `ovf`.
func parseF32(str: string)->{ value: f32, eat: u32, ovf: bool } fail
{
    let {value, eat, ovf} = try parseF64(str)
    if Math.abs(value) > Swag.F32.Max
    {
        if value < 0
        {
            return {value: -Swag.F32.Max, eat: eat, ovf: true}
        }

        return {value: Swag.F32.Max, eat: eat, ovf: true}
    }

    return {value: cast(f32, value), eat: eat, ovf: ovf}
}

// Parses an invariant-culture floating-point number as an `f32`.
public func parseF32Invariant(str: string)->{ value: f32, eat: u32, ovf: bool } fail
{
    let {value, eat, ovf} = try parseF64Invariant(str)
    if Math.abs(value) > Swag.F32.Max
    {
        if value < 0
        {
            return {value: -Swag.F32.Max, eat: eat, ovf: true}
        }

        return {value: Swag.F32.Max, eat: eat, ovf: true}
    }

    return {value: cast(f32, value), eat: eat, ovf: ovf}
}

// Parses the floating-point number at the start of `str`.
//
// Returns the value, the number of bytes consumed in `eat`, and `ovf` set when the value does not
// fit in an `f64`. Signs and the decimal separator are spelled as in the current culture's number
// format.
func parseF64(str: string)->{ value: f64, eat: u32, ovf: bool } fail => try StrConv.Atod.parse(str)

// Parses an invariant-culture floating-point number as an `f64`.
public func parseF64Invariant(str: string)->{ value: f64, eat: u32, ovf: bool } fail
{
    var numberFormat: NumberFormatInfo
    return try StrConv.Atod.parse(str, numberFormat)
}

// Parses the boolean word at the start of `str`.
//
// Accepts `1`, `true`, `TRUE` and `True` for true, and `0`, `false`, `FALSE` and `False` for
// false. Returns the value and the number of bytes consumed in `eat`. Fails with
// [[Core.Errors.SyntaxError]] for any other word.
func parseBool(str: string)->{ value: bool, eat: u32 } fail
{
    var result: #returntype

    let word = Tokenize.alphanumericPrefix(str)
    switch word
    {
    case "1", "true", "TRUE", "True":    result.value = true
    case "0", "false", "FALSE", "False": result.value = false
    default: fail SyntaxError{}
    }

    result.eat = cast(u32, word.count)
    return result
}

// Decodes the rune at the start of `str` and returns it with the number of bytes it occupies.
//
// An invalid sequence returns [[Core.Utf8.RuneError]] with `eat` 1. Fails with
// [[Core.Errors.SyntaxError]] when `str` is empty.
func parseRune(str: string)->{ value: rune, eat: u32 } fail
{
    let byteCount = str.count
    if not byteCount
    {
        fail SyntaxError{}
    }

    let decoded = Utf8.decodeRune(str)
    return {value: decoded.c, eat: decoded.eat}
}

// Returns the identifier at the start of `str`.
//
// An identifier starts with '_' or a Latin-1 letter and continues with '_', Latin-1 letters, and
// digits. These characters are decoded from UTF-8. Fails with [[Core.Errors.SyntaxError]] when
// `str` does not start with one.
func parseIdentifier(str: string)->string fail
{
    let byteCount = str.count
    if not byteCount
    {
        fail SyntaxError{}
    }

    let {c: first, eat: firstBytes} = Utf8.decodeRune(str)
    if first != '_'_rune
    {
        if not Unicode.isLatin1(first)
        {
            fail SyntaxError{}
        }

        if not Latin1.isLetter(cast(u8, first))
        {
            fail SyntaxError{}
        }
    }

    var endByte = firstBytes
    while endByte < byteCount
    {
        let {c, eat} = Utf8.decodeRune(str[endByte to])
        if c != '_'_rune
        {
            if not Unicode.isLatin1(c)
            {
                break
            }

            if not Latin1.isLetterOrDigit(cast(u8, c))
            {
                break
            }
        }

        endByte += eat
    }

    return str[until endByte]
}

// Parses the text at the start of `str` into `result` and returns the number of bytes consumed.
//
// Text that starts with '"' ends at the next '"', and neither quote is stored; other text runs to
// the end of `str`. Fails with [[Core.Errors.SyntaxError]] when `str` is empty, and with
// [[Core.Errors.ParseIncompleteError]] when the closing quote is missing.
func parseString(result: *String, str: string)->u32 fail
{
    let byteCount = str.count
    if not byteCount
    {
        fail SyntaxError{}
    }

    result.clear()

    var isQuoted      = false
    var consumedBytes = 0_u64
    if str[0] == '"'_u8
    {
        isQuoted      = true
        consumedBytes += 1
    }

    while consumedBytes < byteCount
    {
        if consumedBytes >= Swag.U32.Max
        {
            fail OverflowError{"string token exceeds the supported length"}
        }

        if str[consumedBytes] == '"'_u8 and isQuoted
        {
            break
        }

        if str[consumedBytes] == '\\'_u8
        {
            consumedBytes += 1
            if consumedBytes >= Swag.U32.Max
            {
                fail OverflowError{"string token exceeds the supported length"}
            }

            if consumedBytes == byteCount
            {
                fail SyntaxError{}
            }

            switch str[consumedBytes]
            {
            case 't'_u8: result[] += '\t'_u8
            case 'n'_u8: result[] += '\n'_u8
            default:     result[] += str[consumedBytes]
            }
        }
        else
        {
            result[] += str[consumedBytes]
        }

        consumedBytes += 1
    }

    if consumedBytes == byteCount and isQuoted
    {
        fail ParseIncompleteError{}
    }

    if isQuoted
    {
        consumedBytes += 1
    }

    if consumedBytes > Swag.U32.Max
    {
        fail OverflowError{"string token exceeds the supported length"}
    }

    return cast(u32, consumedBytes)
}

// Parses the text at the start of `str` and returns it with the number of bytes consumed.
//
// The rules are those of the overload that fills a caller's [[Core.String]].
func parseString(str: string)->{ value: String, eat: u32 } fail
{
    var result: #returntype
    result.eat = try parseString(&result.value, str)
    return result
}

// Require a complete number, preserving overflow priority over trailing text.
private func(T) requireCompleteNumber(parsed: {value: T, eat: u32, ovf: bool}, byteCount: u64)->T fail
{
    if parsed.ovf
    {
        fail OverflowError{}
    }

    if parsed.eat != byteCount
    {
        fail SyntaxError{}
    }

    return parsed.value
}

// Converts the whole of `str` to an `s8`.
//
// Fails with [[Core.Errors.OverflowError]] when the value does not fit, and with
// [[Core.Errors.SyntaxError]] when `str` holds anything after the number.
func toS8(str: string)->s8 fail
{
    return try requireCompleteNumber(try parseS8(str), str.count)
}

// Converts the whole of `str` to an `s16`, like [[Core.StrConv.toS8]].
func toS16(str: string)->s16 fail
{
    return try requireCompleteNumber(try parseS16(str), str.count)
}

// Converts the whole of `str` to an `s32`, like [[Core.StrConv.toS8]].
func toS32(str: string)->s32 fail
{
    return try requireCompleteNumber(try parseS32(str), str.count)
}

// Converts the whole of `str` to an `s64`, like [[Core.StrConv.toS8]].
func toS64(str: string)->s64 fail
{
    return try requireCompleteNumber(try parseS64(str), str.count)
}

// Converts the whole of `str` to a `u8`, like [[Core.StrConv.toS8]].
func toU8(str: string)->u8 fail
{
    return try requireCompleteNumber(try parseU8(str), str.count)
}

// Converts the whole of `str` to a `u16`, like [[Core.StrConv.toS8]].
func toU16(str: string)->u16 fail
{
    return try requireCompleteNumber(try parseU16(str), str.count)
}

// Converts the whole of `str` to a `u32`, like [[Core.StrConv.toS8]].
func toU32(str: string)->u32 fail
{
    return try requireCompleteNumber(try parseU32(str), str.count)
}

// Converts the whole of `str` to a `u64`, like [[Core.StrConv.toS8]].
func toU64(str: string)->u64 fail
{
    return try requireCompleteNumber(try parseU64(str), str.count)
}

// Converts the whole of `str` to an `f32`, like [[Core.StrConv.toS8]].
func toF32(str: string)->f32 fail
{
    return try requireCompleteNumber(try parseF32(str), str.count)
}

// Converts the whole of `str` to an `f64`, like [[Core.StrConv.toS8]].
func toF64(str: string)->f64 fail
{
    return try requireCompleteNumber(try parseF64(str), str.count)
}

// Converts the whole of `str` to the integer or floating-point type `T`.
//
// The conversion and its failures are those of the matching `toX` function, such as
// [[Core.StrConv.toS32]] for `s32`.
#[Swag.Propagate]
func(T) toNum(str: string)->T fail
{
    #static switch T
    {
    case u8:  return toU8(str)
    case u16: return toU16(str)
    case u32: return toU32(str)
    case u64: return toU64(str)
    case s8:  return toS8(str)
    case s16: return toS16(str)
    case s32: return toS32(str)
    case s64: return toS64(str)
    case f32: return toF32(str)
    case f64: return toF64(str)
    default:  #error("invalid type")
    }

    return 0
}
