#global if #os == Swag.TargetOs.Windows or #os == Swag.TargetOs.Linux

using Core

public impl FontFamily
{
    // Loads the closest installed face for a family name and style, or returns `null` if absent.
    //
    // Available on Windows and Linux. Missing bold or italic traits are synthesized on a
    // separate cached typeface; an ordinary file load and other styles remain unchanged.
    // Linux accepts typographic and legacy family names and preserves collection indices.
    // The result belongs to Pixel until module shutdown; never delete it. File, font, or
    // native loading failures are reported through `fail`. Invalid style values also fail.
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
        return try systemTypeFaceNative(fontFamily, style)
    }

    // Returns owned installed-family names without native font descriptors.
    //
    // Available on Windows and Linux. Names are sorted by their UTF-8 bytes, preserving the
    // order used by the Windows family enumeration. The array and strings belong to the caller;
    // an empty array means no installed families were discovered. Linux uses the process's
    // cached font catalog, including its typographic family names.
    //
    // ```swag
    // for name in Pixel.FontFamily.enumerateSystemFontNames() do
    //     Swag.print(name.toString(), "\n")
    // ```
    func enumerateSystemFontNames()->Array'String
    {
        var result = systemFontNamesNative()
        result.sort(func(a, b) => a <=> b)
        return result
    }
}
