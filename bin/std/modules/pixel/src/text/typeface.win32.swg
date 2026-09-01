#global if #os == Swag.TargetOs.Windows

using Core, Win32, Gdi32, TrueType

// The `ttcf` table tag, in the byte order `GetFontData` reads a tag in.
const TtcfTableTag = 0x66637474'u32

impl TypeFace
{
    // Reads the whole font file behind a device context.
    //
    // `GetFontData` with no table tag returns a single-face file synthesized for the
    // selected font, and for a member of a collection that file is unusable: its
    // table directory still carries the offsets the member had inside the collection,
    // while the collection header those offsets were measured from is gone. Every
    // table then lands short of where it is stated to be — `cmap` reads as a subtable
    // count of tens of thousands, and parsing walks off the end of the buffer.
    //
    // Asking for the `ttcf` table instead returns the collection itself, byte for
    // byte, which the face is then selected from. A font that belongs to no
    // collection answers `GDI_ERROR` for that table, and the plain call is the right
    // one for it.
    //
    // The returned length is tested against `GDI_ERROR` here rather than left to the
    // checked wrapper, because Windows sets no last error for a table a font does not
    // have and a zero last error is reported as success — see `std.win32.001`. Untested, the
    // absent table reads as a length of four gigabytes.
    func readHfontData(hfont: HFONT)->Array'u8 fail
    {
        var result: retval

        let hdc = GetDC(null)
        defer ReleaseDC(null, hdc)

        let previousObject = SelectObject(hdc, cast() hfont)
        defer SelectObject(hdc, previousObject)

        var table            = 0'u32
        let collectionLength = catch GetFontData(hdc, TtcfTableTag, 0, null, 0) as err
        var length           = collectionLength

        if err != null or !collectionLength or collectionLength == GDI_ERROR do
            length = try GetFontData(hdc, 0, 0, null, 0)
        else do
            table = TtcfTableTag

        // Nothing readable behind the handle. An empty buffer is what says so, and
        // the face loader reports it as the empty input it is.
        if length == GDI_ERROR do
            length = 0

        result.resize(cast() length)
        discard GetFontData(hdc, table, 0, result.buffer, cast(DWORD) result.count)
        return result
    }

    // Reads the family name the handle was created for.
    //
    // A collection hands back every one of its faces at once, so this name is what
    // says which of them was asked for.
    func readHfontFamily(hfont: HFONT)->String fail
    {
        var logFont: LOGFONTW
        try GetObjectW(cast() hfont, #sizeof(LOGFONTW), cast(LPVOID) &logFont)

        let length = Utf16.lengthUntilZero(logFont.lfFaceName)
        if !length do
            return ""
        return Utf8.fromUtf16(Swag.makeSlice(&logFont.lfFaceName[0], length))
    }

    // Loads the face `family` names out of the font data GDI returned.
    //
    // A collection's first face is whichever one the file happens to list first
    // rather than the one that was asked for — `msgothic.ttc` leads with `MS Gothic`
    // and holds `MS PGothic` last — so the family has to be matched by name. A member
    // whose names cannot be read is skipped rather than allowed to fail the load, and
    // a collection stating no match falls back to its first face, which is what a
    // system whose enumerated names are localized away from the `name` table gets.
    func loadFaceForFamily(bytes: const [..] u8, family: string, allocator: IAllocator)->#null *Face fail
    {
        let count = try Face.countFaces(bytes)
        if count > 1 and family.count != 0
        {
            for count
            {
                let name = catch Face.familyNameAt(bytes, Swag.index) as err
                if err == null and !Latin1.compare(name, family, ignoreCase: true) do
                    return Face.loadAt(bytes, Swag.index, allocator)
            }
        }

        return Face.load(bytes, allocator)
    }

    // Creates or reuses a cached typeface from a borrowed Windows font handle.
    public func createFromHfont(fullname: string, hfont: HFONT)->*TypeFace fail
    {
        Sync.scopedLock(&lock)

        let str  = String.from(fullname)
        let here = g_HashTypeFace.tryFind(str)
        if here do
            return here.value!

        let allocator = (Swag.getContext().defaultAllocator orelse Swag.getContext().allocator)!

        // Everything that can fail runs before the cached value exists. Dropping a
        // typeface destroys the face it holds, and a typeface built ahead of its face
        // has no face to destroy — the failure path would read an unassigned pointer
        // instead of reporting the failure.
        var buffer = readHfontData(hfont)
        let family = try readHfontFamily(hfont)
        let face   = (try loadFaceForFamily(buffer.toSlice(), family, allocator))!

        let tf = Memory.new'TypeFace(allocator)
        tf.allocationAllocator = allocator
        tf.fullname            = fullname
        tf.face                = face
        tf.faceLoaded          = true

        g_HashTypeFace.add(str, tf)
        return tf
    }
}
