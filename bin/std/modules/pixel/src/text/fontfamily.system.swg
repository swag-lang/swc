#global if #os == Swag.TargetOs.Windows or #os == Swag.TargetOs.Linux

using Core

// Whether the fonts installed on the machine answer lookups in this process.
private enum SystemFontAccess
{
    Undecided     // Decided at the first lookup from how the process was started.
    Allowed
    Refused
}

private var g_SystemFontAccess: SystemFontAccess = .Undecided

public impl FontFamily
{
    // Reports whether the fonts installed on the machine answer lookups in this process.
    //
    // They do in an application. A test run, started with the `swag.test` argument, begins
    // without them: what a test draws must not depend on the machine it runs on, so every
    // system lookup then answers as if no font were installed, including the glyph fallback of
    // [[Pixel.FontCache]]. Typefaces loaded from files or memory are never affected.
    func hasSystemFontAccess()->bool
    {
        if g_SystemFontAccess == .Undecided do
            g_SystemFontAccess = Env.hasArgument("swag.test") ? .Refused : .Allowed
        return g_SystemFontAccess == .Allowed
    }

    // Chooses whether the fonts installed on the machine answer lookups in this process.
    //
    // Only a test of the system font boundary itself turns them on, and turns them off again
    // when it ends. Typefaces already returned stay valid; lookups cached by a caller before
    // the change keep their earlier answer.
    //
    // ```swag
    // Pixel.FontFamily.setSystemFontAccess(true)
    // defer Pixel.FontFamily.setSystemFontAccess(false)
    // let names = Pixel.FontFamily.enumerateSystemFontNames()
    // ```
    func setSystemFontAccess(allowed: bool)
    {
        g_SystemFontAccess = allowed ? .Allowed : .Refused
    }

    // Loads the closest installed face for a family name and style, or returns `null` if absent.
    //
    // Available on Windows and Linux. Missing bold or italic traits are synthesized on a
    // separate cached typeface; an ordinary file load and other styles remain unchanged.
    // Linux accepts typographic and legacy family names and preserves collection indices.
    // The result belongs to Pixel until module shutdown; never delete it. File, font, or
    // native loading failures are reported through `fail`. Invalid style values also fail.
    // Without [[Pixel.FontFamily.hasSystemFontAccess]] every family is absent.
    //
    // ```swag
    // var cache: Pixel.FontCache
    // if let face = try Pixel.FontFamily.createTypeFace("Example Sans", .Bold)
    // {
    //     let font = cache.createFont(face, 20)
    // }
    // ```
    func createTypeFace(fontFamily: string, style: FontFamilyStyle)->*TypeFace? fail
    {
        if cast(u64, style) >= FontFamilyStyle.count do
            fail Errors.BadParameterError{}
        if not hasSystemFontAccess() do
            return null
        return try systemTypeFaceNative(fontFamily, style)
    }

    // Returns owned installed-family names without native font descriptors.
    //
    // Available on Windows and Linux. Names are sorted by their UTF-8 bytes, preserving the
    // order used by the Windows family enumeration. The array and strings belong to the caller;
    // an empty array means no installed families were discovered. Linux uses the process's
    // cached font catalog, including its typographic family names. Without
    // [[Pixel.FontFamily.hasSystemFontAccess]] the array is empty.
    //
    // ```swag
    // for name in Pixel.FontFamily.enumerateSystemFontNames() do
    //     Swag.print(name.toString(), "\n")
    // ```
    func enumerateSystemFontNames()->Array'String
    {
        if not hasSystemFontAccess() do
            return {}
        var result = systemFontNamesNative()
        result.sort(func(a, b) => a <=> b)
        return result
    }
}
