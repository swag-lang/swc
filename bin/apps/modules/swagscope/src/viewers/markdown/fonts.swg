#global internal

using Core, Pixel

private var g_MarkdownFontFamilies: HashTable'(String, [FontFamilyStyle.count] (*TypeFace?))
private var g_MarkdownFontLock:     Sync.Mutex

// Resolve each CSS family list once. Missing system fonts keep the viewer's embedded fallback;
// no document theme installs, downloads or ships font files.
func markdownSystemFaces(names: const [..] string)->[FontFamilyStyle.count] (*TypeFace?)
{
    var key: String
    for name in names
    {
        key += name
        key += ";"
    }

    Sync.scopedLock(&g_MarkdownFontLock)
    if let found = g_MarkdownFontFamilies.tryFind(key) do
        return found.value

    var result: retval
    for name in names
    {
        let family = FontFamily.findSystemFont(name)
        if family.name.isEmpty() do
            continue
        for index in FontFamilyStyle.count do
            result[index] = catch FontFamily.createTypeFace(family, cast(FontFamilyStyle) index)
        if result[0] != null do
            break
    }

    g_MarkdownFontFamilies.add(key, result)
    return result
}
