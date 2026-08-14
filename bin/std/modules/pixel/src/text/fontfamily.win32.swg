#global if #os == Swag.TargetOs.Windows

using Core, Win32, Gdi32

// Describes one Windows face discovered for a font-family style.
public struct SystemFontFaceInfo
{
    public
    {
        name: String       // Windows face name.
        face: LOGFONTW     // Native descriptor returned by GDI.
    }
}

// Describes a Windows font family and the native faces available for its style slots.
public struct SystemFontFamilyInfo
{
    public
    {
        name:  String                                             // Family name.
        faces: [@countof(FontFamilyStyle)] SystemFontFaceInfo     // Face descriptor indexed by [[Pixel.FontFamilyStyle]].
    }
}

impl FontFamily
{
    func enumSubFamily(fa: const *LOGFONTW, _tm: const *TEXTMETRICW, _fontType: DWORD, lParam: LPARAM)->BOOL
    {
        let len = Utf16.lengthZeroTerminated(&fa.lfFaceName[0])
        if !len do
            return TRUE
        let x = Utf8.fromUtf16(@mkslice(&fa.lfFaceName[0], len))

        let ret = cast(*SystemFontFamilyInfo) cast #bit (u64) lParam
        var idx = cast(u64) FontFamilyStyle.Regular

        if fa.lfWeight > FW_REGULAR
        {
            if fa.lfItalic != 0 do
                idx = cast(u64) FontFamilyStyle.BoldItalic
            else do
                idx = cast(u64) FontFamilyStyle.Bold
        }
        elif fa.lfItalic != 0 do
            idx = cast(u64) FontFamilyStyle.Italic

        ret.faces[idx].name = x
        ret.faces[idx].face = fa[]
        return TRUE
    }

    func enumFamily(fa: const *LOGFONTW, _tm: const *TEXTMETRICW, fontType: DWORD, lParam: LPARAM)->BOOL
    {
        if fontType & TRUETYPE_FONTTYPE
        {
            let len = Utf16.lengthZeroTerminated(&fa.lfFaceName[0])
            if !len do
                return TRUE
            let x = Utf8.fromUtf16(@mkslice(&fa.lfFaceName[0], len))

            // Ignore vertical aliases, which Windows prefixes with `@`.
            if x[0] == '@' do
                return TRUE

            // Already here ?
            let ret = cast(*Array'SystemFontFamilyInfo) cast #bit (u64) lParam
            for here in ret[]
            {
                if here.name == x do
                    return TRUE
            }

            var v: SystemFontFamilyInfo
            v.name = x

            let hdc = GetDC(null)
            defer ReleaseDC(null, hdc)
            EnumFontFamiliesExW(hdc, fa, &enumSubFamily, cast #bit (LPARAM) cast(u64) &v, 0)

            ret.add(v)
        }

        return TRUE
    }

    // Returns the font families currently available from Windows.
    public func enumerateSystemFonts()->Array'SystemFontFamilyInfo
    {
        var result: retval

        let hdc = GetDC(null)
        defer ReleaseDC(null, hdc)

        var logFont: LOGFONTW
        logFont.lfCharSet = DEFAULT_CHARSET
        EnumFontFamiliesExW(hdc, &logFont, &enumFamily, cast #bit (LPARAM) cast(u64) &result, 0)

        result.sort(func(a, b) { return a.name <=> b.name })
        return result
    }

    // Finds a Windows font family by name.
    //
    // Returns an empty descriptor when no matching family exists.
    public func findSystemFont(fontFamily: string)->SystemFontFamilyInfo
    {
        let hdc = GetDC(null)
        defer ReleaseDC(null, hdc)

        var arr: Array'SystemFontFamilyInfo
        let v = Utf16.toZeroTerminated(fontFamily)
        EnumFontFamiliesW(hdc, v.buffer, &enumFamily, cast #bit (LPARAM) cast(u64) &arr)

        if arr.isEmpty() do
            return {}
        return arr[0]
    }

    // Creates a cached typeface for the requested descriptor and style.
    //
    // Falls back to the closest available style and returns `null` when the
    // descriptor contains no usable face.
    public func createTypeFace(fontFamily: SystemFontFamilyInfo, style: FontFamilyStyle)->#null *TypeFace fail
    {
        var logFont = fontFamily.faces[cast(u64) style]
        if style == .Regular
        {
            if logFont.name.isEmpty() do
                logFont = fontFamily.faces[cast(u64) FontFamilyStyle.Bold]
        }
        elif style == .Bold
        {
            if logFont.name.isEmpty() do
                logFont = fontFamily.faces[cast(u64) FontFamilyStyle.Regular]
        }
        elif style == .Italic
        {
            if logFont.name.isEmpty() do
                logFont = fontFamily.faces[cast(u64) FontFamilyStyle.BoldItalic]
            if logFont.name.isEmpty() do
                logFont = fontFamily.faces[cast(u64) FontFamilyStyle.Regular]
            if logFont.name.isEmpty() do
                logFont = fontFamily.faces[cast(u64) FontFamilyStyle.Bold]
        }
        elif style == .BoldItalic
        {
            if logFont.name.isEmpty() do
                logFont = fontFamily.faces[cast(u64) FontFamilyStyle.Italic]
            if logFont.name.isEmpty() do
                logFont = fontFamily.faces[cast(u64) FontFamilyStyle.Bold]
            if logFont.name.isEmpty() do
                logFont = fontFamily.faces[cast(u64) FontFamilyStyle.Regular]
        }

        if logFont.name.isEmpty()
        {
            for i in @countof(FontFamilyStyle)
            {
                logFont = fontFamily.faces[i]
                if !logFont.name.isEmpty() do
                    break
            }

            if logFont.name.isEmpty() do
                return null
        }

        let hf = try CreateFontIndirectW(logFont.face)
        defer catch DeleteObject(cast() hf)

        let fontName = Format.toString("%_%", logFont.name, cast(u32) style)
        let typeFace = try TypeFace.createFromHfont(fontName, hf)

        if (style == .Italic or style == .BoldItalic) and !typeFace.isItalic() do
            typeFace.forceItalic = true
        if (style == .Bold or style == .BoldItalic) and !typeFace.isBold() do
            typeFace.forceBold = true

        return typeFace
    }
}
