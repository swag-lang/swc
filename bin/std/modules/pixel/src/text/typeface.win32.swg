#global if #os == Swag.TargetOs.Windows

using Core, Win32, Gdi32, TrueType

// The `ttcf` table tag, in the byte order `GetFontData` reads a tag in.
const TtcfTableTag = 0x66637474'u32

impl TypeFace
{
    // Reads the whole font file behind a device context.
    //
    // `GetFontData` with no table tag returns a single-face file synthesized for the
    // With no table tag, `GetFontData` synthesizes a single-face file for the selected font.
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
        var result: retval

        let hdc = GetDC(null)
        defer ReleaseDC(null, hdc)

        let previousObject = SelectObject(hdc, cast(hfont))
        defer SelectObject(hdc, previousObject)

        var table  = 0'u32
        let collectionLength = catch GetFontData(hdc, TtcfTableTag, 0, null, 0) as err
        var length = collectionLength

        if err != null or not collectionLength or collectionLength == GDI_ERROR do
            length = try GetFontData(hdc, 0, 0, null, 0)
        else do
            table = TtcfTableTag

        // Nothing readable behind the handle. An empty buffer is what says so, and
        // the face loader reports it as the empty input it is.
        if length == GDI_ERROR do
            length = 0

        result.resize(cast(length))
        discard try GetFontData(hdc, table, 0, result.buffer, cast(DWORD, result.count))
        return result
    }

    // Reads the family name the handle was created for.
    //
    // A collection hands back every one of its faces at once, so this name is what
    // says which of them was asked for.
    func readHfontFamily(hfont: HFONT)->String fail
    {
        var logFont: LOGFONTW
        try GetObjectW(cast(hfont), #sizeof(LOGFONTW), cast(LPVOID, &logFont))

        let length = Utf16.lengthUntilZero(logFont.lfFaceName)
        if not length do
            return ""
        return Utf8.fromUtf16(Swag.makeSlice(&logFont.lfFaceName[0], length))
    }

    // Loads the face `family` names out of the font data GDI returned.
    //
    // The first face in a collection may differ from the requested family: for example,
    // `msgothic.ttc` lists `MS Gothic` first and `MS PGothic` last. Match by name; skip faces
    // whose names cannot be read, and fall back to the first face if no name matches (for example,
    // when the system's localized names differ from the `name` table).
    func loadFaceForFamily(bytes: const [..] u8, family: string, allocator: IAllocator)->*Face fail
    {
        let count = try Face.countFaces(bytes)
        if count > 1 and family.count != 0
        {
            for index in count
            {
                let name = catch Face.familyNameAt(bytes, index) as err
                if err == null and not Latin1.compare(name, family, ignoreCase: true) do
                    return try Face.loadAt(bytes, index, allocator)
            }
        }

        return try Face.load(bytes, allocator)
    }

    // Creates or reuses a cached typeface from a borrowed Windows font handle.
    public func createFromHfont(fullName: string, hfont: HFONT)->*TypeFace fail
    {
        Sync.scopedLock(&lock)

        let str  = String.from(fullName)
        let here = g_HashTypeFace.tryFind(str)
        if here do
            return here.value

        let allocator = (Swag.getContext().defaultAllocator orelse Swag.getContext().allocator)!

        // Everything that can fail runs before the cached value exists. Dropping a typeface
        // destroys its face. Build the face first so a failure cannot read an unassigned pointer
        // instead of reporting the original error.
        var buffer = try readHfontData(hfont)
        let family = try readHfontFamily(hfont)
        let face   = try loadFaceForFamily(buffer.toSlice(), family, allocator)

        let tf = Memory.new'TypeFace(allocator)
        tf.allocationAllocator = allocator
        tf.fullName   = fullName
        tf.face       = face
        tf.faceLoaded = true

        g_HashTypeFace.add(str, tf)
        return tf
    }
}
