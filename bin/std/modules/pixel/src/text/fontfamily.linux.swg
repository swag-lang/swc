#global if #os == Swag.TargetOs.Linux

using Core

// Describes one installed Linux font face with owned names and file metadata.
public struct SystemFontFaceInfo
{
    public
    {
        name: String           // Typographic style name of the selected face.
        face: FontFileFace     // Owned file path, collection index, and style metadata.
    }
}

// Describes a Linux font family and the closest installed face for each style.
//
// Descriptors own their metadata independently of the process-wide discovery snapshot.
// Several style slots may refer to the same physical face when a family has fewer styles.
public struct SystemFontFamilyInfo
{
    public
    {
        name:  String     // Typographic family name, or empty for an unsuccessful lookup.
        faces: [FontFamilyStyle.count] SystemFontFaceInfo     // Faces indexed by [[Pixel.FontFamilyStyle]].
    }
}

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

    // Returns owned descriptors for the installed Linux font families in case-insensitive order.
    //
    // Discovery uses [[Pixel.FontCatalog.loadSystem]] once per process. Unreadable trees and
    // unsupported files are skipped; no readable faces produces an empty array. Each slot
    // selects the closest installed slant, width, and weight using [[Pixel.FontCatalog.findFace]].
    // Fontconfig aliases are not resolved. Later filesystem changes do not refresh this snapshot.
    public func enumerateSystemFonts()->Array'SystemFontFamilyInfo
    {
        Sync.scopedLock(&g_LinuxFontFallbackLock)
        ensureSystemFontCatalog()
        var result: #returntype
        for &face in g_LinuxFontFallback.catalog.toSlice()
        {
            if result.isEmpty() or Utf8.compare(result.back().name.toString(), face.metadata.typographicFamilyName.toString(), .UnicodeNoCase) != 0 do
                result.add(SystemFontFamilyInfo{name: face.metadata.typographicFamilyName})
            let family = result.backPtr()
            for i in FontFamilyStyle.count
            {
                let slot  = &family.faces[i]
                let style = cast(FontFamilyStyle, i)
                if slot.face.path.isEmpty() or fontCatalogStyleScore(face, style) < fontCatalogStyleScore(&slot.face, style)
                {
                    slot.name = face.metadata.typographicStyleName
                    slot.face = face[]
                }
            }
        }

        return result
    }

    // Finds an installed Linux family by typographic or legacy name, ignoring case.
    //
    // Uses the same discovery snapshot as [[Pixel.FontFamily.enumerateSystemFonts]]. Returns
    // an empty descriptor when absent; otherwise each slot owns its closest installed face.
    public func findSystemFont(fontFamily: string)->SystemFontFamilyInfo
    {
        Sync.scopedLock(&g_LinuxFontFallbackLock)
        ensureSystemFontCatalog()
        var result: #returntype
        for i in FontFamilyStyle.count
        {
            if let face = g_LinuxFontFallback.catalog.findFace(fontFamily, cast(FontFamilyStyle, i))
            {
                if result.name.isEmpty() do
                    result.name = face.metadata.typographicFamilyName
                result.faces[i] = SystemFontFaceInfo{face.metadata.typographicStyleName, face[]}
            }
        }

        return result
    }

    // Loads a process-cached typeface from an owned Linux family descriptor.
    //
    // Selects the requested slot, or the closest available face when that slot is empty.
    // Returns `null` for an empty descriptor. File and font decoding errors fail. Missing bold
    // and italic traits are synthesized without changing other cached styles. Never delete
    // the returned pointer; it remains valid until module shutdown. Invalid style values fail.
    public func createTypeFace(fontFamily: SystemFontFamilyInfo, style: FontFamilyStyle)->*TypeFace? fail
    {
        if cast(u64, style) >= FontFamilyStyle.count do
            fail Errors.BadParameterError{}
        var selected = fontFamily.faces[cast(u64, style)].face
        if selected.path.isEmpty()
        {
            var score = 0xFFFFFFFF'u32
            for &slot in fontFamily.faces
            {
                if slot.face.path.isEmpty() do
                    continue
                let candidate = fontCatalogStyleScore(&slot.face, style)
                if candidate < score
                {
                    selected = slot.face
                    score    = candidate
                }
            }
        }

        if selected.path.isEmpty() do
            return null
        return try TypeFace.loadStyledAt(selected.path.toString(), selected.faceIndex, style)
    }

    internal func systemTypeFaceNative(fontFamily: string, style: FontFamilyStyle)->*TypeFace? fail
    {
        Sync.scopedLock(&g_LinuxFontFallbackLock)
        ensureSystemFontCatalog()
        let face = g_LinuxFontFallback.catalog.findFace(fontFamily, style)
        if not face do
            return null
        return try TypeFace.loadStyledAt(face.path.toString(), face.faceIndex, style)
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
