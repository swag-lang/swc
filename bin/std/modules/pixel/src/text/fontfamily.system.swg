#global if #os == Swag.TargetOs.Windows or #os == Swag.TargetOs.Linux

using Core

public impl FontFamily
{
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
