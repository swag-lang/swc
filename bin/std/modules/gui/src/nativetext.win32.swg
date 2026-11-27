#global if #os == Swag.TargetOs.Windows
#global namespace NativeText

using Core, Win32

// Encodes `text` as zero-terminated ANSI text in `codePage`, or returns an empty array when it cannot.
//
// `CF_TEXT` uses the Windows ANSI code page, not UTF-8. Zero selects the system code page.
func encodeAnsi(text: string, codePage: u32 = 0)->Array!{u8}
{
    var result: #returntype
    let wide = Utf16.toZeroTerminated(text)
    if wide.count > Swag.S32.Max
    {
        return result
    }

    let length = cast(s32, wide.count)
    let count  = WideCharToMultiByte(codePage, 0, wide.buffer, length, null, 0, null, null)
    if count <= 0
    {
        return result
    }

    result.resize(cast(u64, count))
    if WideCharToMultiByte(codePage, 0, wide.buffer, length, result.buffer, count, null, null) != count
    {
        result.clear()
    }

    return result
}

// Decodes zero-terminated UTF-16 bytes into UTF-8, or returns an empty string when `bytes` holds no terminator.
//
// External native strings must carry a terminator within their actual storage extent.
func decodeUnicode(bytes: const [..] u8)->String
{
    var result: #returntype
    if bytes.count < 2 or bytes.count % 2
    {
        return result
    }

    let wide  = Swag.makeSlice(cast(const [*] u16, bytes.buffer), bytes.count / 2)
    let count = Utf16.lengthUntilZero(wide)
    if count == wide.count
    {
        return result
    }

    return Utf8.fromUtf16(wide[until count])
}

// Decodes zero-terminated ANSI bytes in `codePage` into UTF-8, or returns an empty string when `bytes` holds no terminator.
func decodeAnsi(bytes: const [..] u8, codePage: u32 = 0)->String
{
    var result: #returntype
    var length = 0_u64
    while length < bytes.count and bytes[length] != 0
    {
        length += 1
    }

    if length == bytes.count or length == 0 or length > Swag.S32.Max
    {
        return result
    }

    let count = MultiByteToWideChar(codePage, 0, bytes.buffer, cast(s32, length), null, 0)
    if count <= 0
    {
        return result
    }

    var wide: Array!{u16}
    wide.resize(cast(u64, count))
    if MultiByteToWideChar(codePage, 0, bytes.buffer, cast(s32, length), wide.buffer, count) != count
    {
        return result
    }

    return Utf8.fromUtf16(wide.toSlice())
}
