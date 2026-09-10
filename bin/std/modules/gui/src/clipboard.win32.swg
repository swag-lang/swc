#global if #os == Swag.TargetOs.Windows
#global namespace Clipboard
#global public

using Core, Win32, Pixel

// Names the value format type.
alias ValueFormat = u64

private var g_PngFormat: UINT

// The clipboard takes ownership only when publication succeeds. A failed transfer keeps
// ownership here, and the movable block is unlocked before either transfer or destruction.
private func addNativeData(fmt: UINT, bytes: const [..] u8)
{
    let hglob = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, bytes.count)
    if not hglob do
        return
    var transferred = false
    defer
    {
        if not transferred do
            discard GlobalFree(hglob)
    }

    let buffer = cast([*] u8?) GlobalLock(hglob)
    if not buffer do
        return
    Memory.copy(buffer, bytes.buffer, bytes.count)
    discard GlobalUnlock(hglob)
    transferred = SetClipboardData(fmt, hglob) != null
}

// Registers a named native clipboard format.
func registerFormat(name: string)->ValueFormat fail
{
    return try RegisterClipboardFormatA(name.buffer)
}

// Reports whether the clipboard contains `fmt`.
func hasFormat(fmt: ValueFormat)->bool
{
    if g_Fake.enabled do
        return fakeFind(fmt) != null

    if not OpenClipboard(GetDesktopWindow()) do
        return false
    defer discard CloseClipboard()

    return IsClipboardFormatAvailable(cast(UINT) fmt) ? true : false
}

// Reports whether `fmt` exists and, when provided, carries the requested type fingerprint.
func hasTypedData(fmt: ValueFormat, type: typeinfo?)->bool
{
    if g_Fake.enabled
    {
        let entry = fakeFind(fmt)
        if not entry do
            return false
        return not type or entry.crc == type.crc
    }

    if not OpenClipboard(GetDesktopWindow()) do
        return false
    defer discard CloseClipboard()

    if not IsClipboardFormatAvailable(cast(UINT) fmt) do
        return false
    if not type do
        return true

    let hglob = GetClipboardData(cast(UINT) fmt)
    let data  = cast([*] u8?) GlobalLock(hglob)
    if not data do
        return false
    defer discard GlobalUnlock(hglob)
    catch
    {
        let payload = TypedPayload.decode(Swag.makeSlice(data, GlobalSize(hglob)))
        return payload.matches(type)
    }
    else {}
    return false
}

// Adds or replaces a raw payload and optional type fingerprint without clearing other formats.
func addTypedData(fmt: ValueFormat, type: typeinfo?, data: const [..] u8)
{
    if g_Fake.enabled do
        return fakeAddTypedData(fmt, type, data)

    if not OpenClipboard(GetDesktopWindow()) do
        return
    defer discard CloseClipboard()
    let payload = TypedPayload{crc: type ? type.crc : 0, data: data}
    let bytes   = payload.encode()
    addNativeData(cast(UINT) fmt, bytes.toSlice())
}

// Returns a copy of the raw payload stored under `fmt`, when its optional type matches.
func getTypedData(fmt: ValueFormat, type: typeinfo?)->Array'u8
{
    if g_Fake.enabled do
        return fakeGetTypedData(fmt, type)

    var result: retval

    if not OpenClipboard(GetDesktopWindow()) do
        return result
    defer discard CloseClipboard()

    if not IsClipboardFormatAvailable(cast(UINT) fmt) do
        return result
    let hglob = GetClipboardData(cast(UINT) fmt)
    let data  = cast([*] u8?) GlobalLock(hglob)
    if not data do
        return result
    defer discard GlobalUnlock(hglob)
    catch
    {
        let payload = TypedPayload.decode(Swag.makeSlice(data, GlobalSize(hglob)))
        if payload.matches(type) and payload.data do
            result.add(payload.data)
    }
    else {}

    return result
}

// Reports whether the clipboard contains a decodable image.
func hasImage()->bool
{
    if g_Fake.enabled do
        return g_Fake.hasImg

    if not OpenClipboard(GetDesktopWindow()) do
        return false
    defer discard CloseClipboard()

    if IsClipboardFormatAvailable(CF_DIB) do
        return true
    if IsClipboardFormatAvailable(g_PngFormat) do
        return true

    return false
}

// Replaces the clipboard contents with `image` in native bitmap and PNG formats.
func addImage(image: Image)
{
    // Mirrors the OS path below: adding an image empties the clipboard first
    if g_Fake.enabled
    {
        fakeClear()
        if not image.isValid() do
            return
        g_Fake.hasImg = true
        g_Fake.img    = Image.create(image.width, image.height, image.pixelFormat, image.pixels.toSlice())
        return
    }

    if not OpenClipboard(GetDesktopWindow()) do
        return
    defer discard CloseClipboard()
    discard EmptyClipboard()

    // Pixel owns DIB channel ordering, row padding, and straight-alpha conversion.
    let dib = catch image.encodeToBytes("clipboard.bmp", Bmp.EncodeOptions{fileHeader: false}) as dibError
    if dibError == null do
        addNativeData(CF_DIB, dib.toSlice())

    let png = catch image.encodeToBytes("clipboard.png", Png.EncodeOptions{compressionLevel: .NoCompression}) as pngError
    if pngError == null do
        addNativeData(g_PngFormat, png.toSlice())
}

// Returns a decoded copy of the clipboard image, or an invalid image when unavailable.
func getImage()->Image
{
    var result: retval

    if g_Fake.enabled
    {
        if g_Fake.hasImg do
            result = g_Fake.img
        return result
    }

    if not OpenClipboard(GetDesktopWindow()) do
        return result
    defer discard CloseClipboard()

    // PNG
    if IsClipboardFormatAvailable(g_PngFormat)
    {
        let hglob = GetClipboardData(g_PngFormat)
        if hglob
        {
            let size = GlobalSize(hglob)
            let pz   = cast([*] u8?) GlobalLock(hglob)
            if not pz do
                return result
            defer discard GlobalUnlock(hglob)
            return catch Image.decode("clipboard.png", Swag.makeSlice(pz, size), {})
        }
    }

    // DIB
    if IsClipboardFormatAvailable(CF_DIB)
    {
        let hglob = GetClipboardData(CF_DIB)
        if hglob
        {
            let size = GlobalSize(hglob)
            let pz   = cast([*] u8?) GlobalLock(hglob)
            if not pz do
                return result
            defer discard GlobalUnlock(hglob)
            return catch Image.decode("clipboard.bmp", Swag.makeSlice(pz, size), {})
        }
    }

    return result
}

// Reports whether the clipboard contains text.
func hasString()->bool
{
    if g_Fake.enabled do
        return g_Fake.hasStr

    if not OpenClipboard(GetDesktopWindow()) do
        return false
    defer discard CloseClipboard()

    if IsClipboardFormatAvailable(CF_UNICODETEXT) do
        return true
    if IsClipboardFormatAvailable(CF_TEXT) do
        return true

    return false
}

// Adds or replaces UTF-8 text in UTF-16 and legacy formats without clearing other formats.
func addString(str: string)
{
    writeString(str, false)
}

// Replaces every clipboard format with UTF-8 text in UTF-16 and legacy formats.
//
// Use this for a standalone copy action. Use [[Clipboard.addString]] to attach text to
// an existing clipboard value while preserving its other formats.
func setString(str: string)
{
    writeString(str, true)
}

private func writeString(str: string, replace: bool)
{
    if g_Fake.enabled
    {
        if replace do
            fakeClear()
        g_Fake.hasStr = true
        g_Fake.str    = str
        return
    }

    if not OpenClipboard(GetDesktopWindow()) do
        return
    defer discard CloseClipboard()

    // Claim ownership before publishing a new copy, so older rich formats cannot win on paste.
    if replace and not EmptyClipboard() do
        return

    let ansi = NativeText.encodeAnsi(str)
    if ansi.count do
        addNativeData(CF_TEXT, ansi.toSlice())
    let wide = Utf16.toZeroTerminated(str)
    addNativeData(CF_UNICODETEXT, Swag.makeSlice(cast(const [*] u8) wide.storage(), wide.count * 2))
}

// Returns clipboard text converted to UTF-8, or an empty string when unavailable.
func getString()->String
{
    var result: retval

    if g_Fake.enabled
    {
        if g_Fake.hasStr do
            result = g_Fake.str
        return result
    }

    if not OpenClipboard(GetDesktopWindow()) do
        return result
    defer discard CloseClipboard()

    let formats = [CF_UNICODETEXT, CF_TEXT]
    for format in formats
    {
        if not IsClipboardFormatAvailable(format) do
            continue
        let hglob = GetClipboardData(format)
        let data  = cast([*] u8?) GlobalLock(hglob)
        if not data do
            continue
        defer discard GlobalUnlock(hglob)
        let bytes = Swag.makeSlice(data, GlobalSize(hglob))
        return format == CF_UNICODETEXT ? NativeText.decodeUnicode(bytes) : NativeText.decodeAnsi(bytes)
    }

    return result
}

// Removes every value from the clipboard.
func clear()
{
    if g_Fake.enabled
    {
        fakeClear()
        return
    }

    if not OpenClipboard(GetDesktopWindow()) do
        return
    defer discard CloseClipboard()
    discard EmptyClipboard()
}

#init
{
    g_PngFormat = catch RegisterClipboardFormatA(("PNG").buffer)
}
