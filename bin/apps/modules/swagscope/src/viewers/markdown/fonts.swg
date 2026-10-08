#global internal
#global namespace Viewers.MarkdownText

using Core, Pixel

private var g_FontFamilies: HashTable'(String, [FontFamilyStyle.count] (*TypeFace?))
private var g_FontLock:     Sync.Mutex

// Returns the type faces of the first installed system family among `names`, one per style.
//
// Each family list is resolved once. Missing system fonts keep the viewer's embedded fallback;
// no document theme installs, downloads or ships font files.
func systemFaces(names: const [..] string)->[FontFamilyStyle.count] (*TypeFace?)
{
    var key: String
    for name in names
    {
        key += name
        key += ";"
    }

    Sync.scopedLock(&g_FontLock)
    if let found = g_FontFamilies.tryFind(key) do
        return found.value

    var result: retval
    for name in names
    {
        let family = FontFamily.findSystemFont(name)
        if family.name.isEmpty() do
            continue
        for index in FontFamilyStyle.count do
            result[index] = catch FontFamily.createTypeFace(family, cast(FontFamilyStyle, index))
        if result[0] != null do
            break
    }

    g_FontFamilies.add(key, result)
    return result
}
