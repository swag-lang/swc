#global if #os == Swag.TargetOs.Windows
#global namespace NativeText

using Core, Win32

// CF_TEXT uses the Windows ANSI code page, not UTF-8. Zero selects the system code page.
func encodeAnsi(text: string, codePage: u32 = 0)->Array'u8
{
    var result: retval
    let wide = Utf16.toZeroTerminated(text)
    if wide.count > Swag.S32.Max do
        return result
    let length = cast(s32) wide.count
    let count  = WideCharToMultiByte(codePage, 0, wide.buffer, length, null, 0, null, null)
    if count <= 0 do
        return result
    result.resize(cast(u64) count)
    if WideCharToMultiByte(codePage, 0, wide.buffer, length, result.buffer, count, null, null) != count do
        result.clear()
    return result
}

// External native strings must carry a terminator within their actual storage extent.
func decodeUnicode(bytes: const [..] u8)->String
{
    var result: retval
    if bytes.count < 2 or bytes.count % 2 do
        return result
    let wide  = Swag.makeSlice(cast(const [*] u16) bytes.buffer, bytes.count / 2)
    let count = Utf16.lengthUntilZero(wide)
    if count == wide.count do
        return result
    return Utf8.fromUtf16(wide[0 until count])
}

func decodeAnsi(bytes: const [..] u8, codePage: u32 = 0)->String
{
    var result: retval
    var length = 0'u64
    while length < bytes.count and bytes[length] != 0 do
        length += 1
    if length == bytes.count or length == 0 or length > Swag.S32.Max do
        return result
    let count = MultiByteToWideChar(codePage, 0, bytes.buffer, cast(s32) length, null, 0)
    if count <= 0 do
        return result
    var wide: Array'u16
    wide.resize(cast(u64) count)
    if MultiByteToWideChar(codePage, 0, bytes.buffer, cast(s32) length, wide.buffer, count) != count do
        return result
    return Utf8.fromUtf16(wide.toSlice())
}
