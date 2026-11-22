#global if #os == Swag.TargetOs.Windows

using Core, Win32, Win32.Gdi32, TrueType

// The `ttcf` table tag, in the byte order `GetFontData` reads a tag in.
const TtcfTableTag = 0x66637474'u32

impl TypeFace
{
    // Reads the whole font file behind a device context.
    //
    // When called without a table tag, `GetFontData` synthesizes a single-face file for the selected font.
    // A collection member cannot use that file: its table offsets refer to the collection, whose
    // header is gone. Reading those offsets can make `cmap` report tens of thousands of
    // subtables and send parsing past the end of the buffer.
    //
    // Asking for the `ttcf` table instead returns the collection itself, byte for
    // byte, which the face is then selected from. A font that belongs to no
    // collection answers `GDI_ERROR` for that table, and the plain call is the right
    // one for it.
    //
    // A missing collection table is an ordinary fallback to the standalone font. The checked
    // wrapper reports the failed query even when Windows supplies no extended error code.
    func readHfontData(hfont: HFONT)->Array'u8 fail
    {
        var result: #returntype

        let hdc = GetDC(null)
        defer ReleaseDC(null, hdc)

        let previousObject = SelectObject(hdc, cast(HGDIOBJ, hfont))
        defer SelectObject(hdc, previousObject)

        var table = 0'u32
        var errOutcome:       Swag.Error
        var collectionLength: #decltype(expect GetFontData(hdc, TtcfTableTag, 0, null, 0))
        catch { collectionLength = try GetFontData(hdc, TtcfTableTag, 0, null, 0) } as errOutcome
        let err    = errOutcome.value()
        var length = collectionLength

        if err != null or not collectionLength or collectionLength == GDI_ERROR do
            length = try GetFontData(hdc, 0, 0, null, 0)
        else do
            table = TtcfTableTag

        // Nothing readable behind the handle. An empty buffer is what says so, and
        // the face loader reports it as the empty input it is.
        if length == GDI_ERROR do
            length = 0

        result.resize(cast(u64, length))
        discard try GetFontData(hdc, table, 0, result.buffer, cast(DWORD, result.count))
        return result
    }

    // Reads the selected font attributes from a borrowed Windows font handle.
    func readHfontLogFont(hfont: HFONT)->LOGFONTW fail
    {
        var logFont: LOGFONTW
        try GetObjectW(cast(HANDLE, hfont), #sizeof(LOGFONTW), cast(LPVOID, &logFont))
        return logFont
    }

    // Loads the face matching the family and style GDI selected from its font data.
    //
    // A collection can contain multiple faces with the same family name. Prefer the closest
    // weight with the requested slant, while preserving the first face as a fallback when names
    // cannot be matched.
    internal func loadFaceForFamily(bytes: const [..] u8, family: string, weight: LONG, italic: bool, allocator: IAllocator)->*Face fail
    {
        let count = try Face.countFaces(bytes)
        if count > 1 and family.count != 0
        {
            var requestedWeight = weight
            if requestedWeight == FW_DONTCARE do
                requestedWeight = FW_REGULAR
            let targetWeight = cast(u16, requestedWeight)

            var bestIndex: u32?
            var bestScore = 4000'u32
            for index in count
            {
                var errOutcome: Swag.Error
                var metadata:   #decltype(expect Face.metadataAt(bytes, index))
                catch { metadata = try Face.metadataAt(bytes, index) } as errOutcome
                let err = errOutcome.value()
                if err != null or Latin1.compare(metadata.familyName, family, ignoreCase: true) do
                    continue

                let weightDistance = metadata.weight > targetWeight ? metadata.weight - targetWeight : targetWeight - metadata.weight
                let boldPenalty    = metadata.style.has(.Bold) == (targetWeight >= FW_SEMIBOLD) ? 0'u32 : 1000'u32
                let italicPenalty  = metadata.style.has(.Italic) == italic ? 0'u32 : 2000'u32
                let score          = italicPenalty + boldPenalty + cast(u32, weightDistance)
                if score < bestScore
                {
                    bestIndex = index
                    bestScore = score
                }
            }

            if let selectedIndex = bestIndex do
                return try Face.loadAt(bytes, selectedIndex, allocator)
        }

        return try Face.load(bytes, allocator)
    }

    // Creates or reuses a cached typeface from a borrowed Windows font handle.
    //
    // For a font collection, matches the face by family, then by the handle's requested weight
    // and slant.
    public func createFromHfont(fullName: string, hfont: HFONT)->*TypeFace fail
    {
        Sync.scopedLock(&lock)

        let key  = TypeFaceCacheKey{String.from(fullName), 0}
        let here = g_HashTypeFace.tryFind(key)
        if here do
            return here.value

        let allocator = unwrap (Swag.getContext().defaultAllocator orelse Swag.getContext().allocator)

        // Everything that can fail runs before the cached value exists. Dropping a typeface
        // destroys its face. Build the face first so a failure cannot read an unassigned pointer
        // instead of reporting the original error.
        var buffer  = try readHfontData(hfont)
        let logFont = try readHfontLogFont(hfont)
        let length  = Utf16.lengthUntilZero(logFont.lfFaceName)
        let family  = length ? Utf8.fromUtf16(Swag.makeSlice(&logFont.lfFaceName[0], length)) : ""
        let face    = try loadFaceForFamily(buffer.toSlice(), family, logFont.lfWeight, logFont.lfItalic != 0, allocator)

        let tf = Memory.new'TypeFace(allocator)
        tf.allocationAllocator = allocator
        tf.fullName   = fullName
        tf.face       = face
        tf.faceLoaded = true

        g_HashTypeFace.add(key, tf)
        return tf
    }
}
