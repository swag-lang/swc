#global if #os == Swag.TargetOs.Windows
#global namespace Clipboard
#global public

using Core, Win32, Pixel

// Names the value format type.
alias ValueFormat = u64

private var g_PngFormat: UINT

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

    if !OpenClipboard(GetDesktopWindow()) do
        return false
    defer discard CloseClipboard()

    return IsClipboardFormatAvailable(cast(UINT) fmt) ? true : false
}

// Reports whether `fmt` exists and, when provided, carries the requested type fingerprint.
func hasTypedData(fmt: ValueFormat, type: #null typeinfo)->bool
{
    if g_Fake.enabled
    {
        let entry = fakeFind(fmt)
        if !entry do
            return false
        return !type or entry.crc == type.crc
    }

    if !OpenClipboard(GetDesktopWindow()) do
        return false
    defer discard CloseClipboard()

    if !IsClipboardFormatAvailable(cast(UINT) fmt) do
        return false
    if !type do
        return true

    let hglob = GetClipboardData(cast(UINT) fmt)
    let pz    = cast(*u32) GlobalLock(hglob)!
    defer discard GlobalUnlock(pz)
    return pz[] == type.crc
}

// Adds or replaces a raw payload and optional type fingerprint without clearing other formats.
func addTypedData(fmt: ValueFormat, type: #null typeinfo, data: const [..] u8)
{
    if g_Fake.enabled do
        return fakeAddTypedData(fmt, type, data)

    if !OpenClipboard(GetDesktopWindow()) do
        return
    defer discard CloseClipboard()
    let hglob = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, data.count + #sizeof(u32) + #sizeof(u64))
    let pz    = cast([*] u8) GlobalLock(hglob)!
    defer discard GlobalUnlock(pz)

    // Store type CRC
    var pzi = cast([*] u32) pz
    pzi[] = type ? type.crc : 0
    pzi   += 1

    // Store data size
    var pzu = cast([*] u64) pzi
    pzu[] = data.count
    pzu   += 1

    // Store data
    Memory.copy(pzu, data.buffer, data.count)
    discard SetClipboardData(cast(UINT) fmt, hglob)
}

// Returns a copy of the raw payload stored under `fmt`, when its optional type matches.
func getTypedData(fmt: ValueFormat, type: #null typeinfo)->Array'u8
{
    if g_Fake.enabled do
        return fakeGetTypedData(fmt, type)

    var result: retval

    if !OpenClipboard(GetDesktopWindow()) do
        return result
    defer discard CloseClipboard()

    if IsClipboardFormatAvailable(cast(UINT) fmt)
    {
        let hglob = GetClipboardData(cast(UINT) fmt)
        if hglob
        {
            let pz = cast([*] u8) GlobalLock(hglob)!
            defer discard GlobalUnlock(pz)

            // Get type CRC, check this is correct
            var pzi = cast([*] u32) pz
            if type and pzi[] != type.crc do
                return result
            pzi += 1

            // Get data count
            var pzu   = cast([*] u64) pzi
            let count = pzu[]
            pzu += 1

            result.add(Swag.makeSlice(cast([*] u8) pzu, count))
            return result
        }
    }

    return result
}

// Reports whether the clipboard contains a decodable image.
func hasImage()->bool
{
    if g_Fake.enabled do
        return g_Fake.hasImg

    if !OpenClipboard(GetDesktopWindow()) do
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
        if !image.isValid() do
            return
        g_Fake.hasImg = true
        g_Fake.img    = Image.create(image.width, image.height, image.pixelFormat, image.pixels.toSlice())
        return
    }

    if !OpenClipboard(GetDesktopWindow()) do
        return
    defer discard CloseClipboard()
    discard EmptyClipboard()

    // BITMAP
    #scope
    {
        let size  = #sizeof(Bmp.Header) + image.byteCount
        let hglob = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, size)
        let buf   = cast([*] u8) GlobalLock(hglob)!

        let header = cast(*Bmp.Header) buf
        header.biSize        = #sizeof(Bmp.Header)
        header.biWidth       = image.width
        header.biHeight      = image.height
        header.biPlanes      = 1
        header.biCompression = Bmp.BI_RGB
        header.biBitCount    = image.bitsPerPixel

        let datas = buf + #sizeof(Bmp.Header)
        Memory.copy(datas, image.pixels.buffer, image.byteCount)

        discard GlobalUnlock(buf)
        discard SetClipboardData(CF_DIB, hglob)
    }

    // PNG
    #scope(Png)
    {
        var opt: Png.EncodeOptions

        opt.compressionLevel = .NoCompression     // We want best speed
        var buffer = catch image.encode("clipboard.png", opt) as encodeError
        if encodeError != null do
            break to Png

        let hglob = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, buffer.count())
        let buf   = cast([*] u8) GlobalLock(hglob)!

        var bufCur = buf
        for b in buffer
        {
            Memory.copy(bufCur, b.data, b.count)
            bufCur += b.count
        }

        discard GlobalUnlock(buf)
        discard SetClipboardData(g_PngFormat, hglob)
    }
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

    if !OpenClipboard(GetDesktopWindow()) do
        return result
    defer discard CloseClipboard()

    // PNG
    if IsClipboardFormatAvailable(g_PngFormat)
    {
        let hglob = GetClipboardData(g_PngFormat)
        if hglob
        {
            let size = GlobalSize(hglob)
            let pz   = cast([*] u8) GlobalLock(hglob)!
            defer discard GlobalUnlock(pz)
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
            let pz   = cast([*] u8) GlobalLock(hglob)!
            defer discard GlobalUnlock(pz)
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

    if !OpenClipboard(GetDesktopWindow()) do
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
    if g_Fake.enabled
    {
        g_Fake.hasStr = true
        g_Fake.str    = str
        return
    }

    if !OpenClipboard(GetDesktopWindow()) do
        return
    defer discard CloseClipboard()

    // Ansi/utf8
    {
        let hglob = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, str.count + 1)
        let pz    = cast([*] u8) GlobalLock(hglob)!
        Memory.copy(pz, str.buffer, str.count)
        pz[str.count] = 0
        discard GlobalUnlock(pz)
        discard SetClipboardData(CF_TEXT, hglob)
    }

    // Utf16
    {
        let hglob = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, str.count * 2 + 2)
        let pz    = cast([*] u16) GlobalLock(hglob)!
        let u     = Utf16.fromUtf8(str)
        Memory.copy(pz, u.buffer, u.count * 2)
        pz[u.count] = 0
        discard GlobalUnlock(pz)
        discard SetClipboardData(CF_UNICODETEXT, hglob)
    }
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

    if !OpenClipboard(GetDesktopWindow()) do
        return result
    defer discard CloseClipboard()

    // Unicode (Utf-16) text
    if IsClipboardFormatAvailable(CF_UNICODETEXT)
    {
        let hglob = GetClipboardData(CF_UNICODETEXT)
        if hglob
        {
            let pz = cast([*] u16) GlobalLock(hglob)!
            result = Utf8.fromUtf16(Swag.makeSlice(pz, Utf16.lengthZeroTerminated(pz)))
            discard GlobalUnlock(pz)
            return result
        }
    }

    // Normal text
    if IsClipboardFormatAvailable(CF_TEXT)
    {
        let hglob = GetClipboardData(CF_TEXT)
        if hglob
        {
            let pz = cast([*] u8) GlobalLock(hglob)!
            result = Swag.makeString(pz, (cast(cstring) pz).count)
            discard GlobalUnlock(pz)
            return result
        }
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

    if !OpenClipboard(GetDesktopWindow()) do
        return
    defer discard CloseClipboard()
    discard EmptyClipboard()
}

#init
{
    g_PngFormat = catch RegisterClipboardFormatA(("PNG").buffer)
}
