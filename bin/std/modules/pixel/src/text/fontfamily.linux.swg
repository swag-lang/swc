#global if #os == Swag.TargetOs.Linux

using Core

private var g_LinuxFontFallbackLock:  Swag.Mutex
private var g_LinuxFontFallback:      FontCatalogFallbackCache
private var g_LinuxFontFallbackReady: bool

impl FontFamily
{
    // Caller holds g_LinuxFontFallbackLock for both discovery and subsequent access.
    private func ensureSystemFontCatalog()
    {
        if not g_LinuxFontFallbackReady
        {
            g_LinuxFontFallback.setCatalog(FontCatalog.loadSystem(),
                                           ["DejaVu Sans", "Liberation Sans", "Noto Sans", "Noto Sans Symbols2", "Noto Color Emoji"])
            g_LinuxFontFallbackReady = true
        }
    }

    internal func systemFontNamesNative()->Array'String
    {
        Sync.scopedLock(&g_LinuxFontFallbackLock)
        ensureSystemFontCatalog()
        return g_LinuxFontFallback.catalog.familyNames()
    }

    internal func findSystemFallback(c: rune, bold, italic: bool)->*TypeFace?
    {
        if not isFontFallbackRune(c) do
            return null
        Sync.scopedLock(&g_LinuxFontFallbackLock)
        ensureSystemFontCatalog()
        let style = bold ? (italic ? FontFamilyStyle.BoldItalic : .Bold) : (italic ? FontFamilyStyle.Italic : .Regular)
        return g_LinuxFontFallback.find(c, style)
    }
}
