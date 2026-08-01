#global if #os == Swag.TargetOs.Windows

using Core, Win32, Gdi32, TrueType

impl TypeFace
{
    func readHfontData(hfont: HFONT)->Array'u8 fail
    {
        var result: retval

        let hdc = GetDC(null)
        defer ReleaseDC(null, hdc)

        let previousObject = SelectObject(hdc, cast() hfont)
        defer SelectObject(hdc, previousObject)

        let outFontBufferLen = GetFontData(hdc, 0, 0, null, 0)
        result.resize(cast() outFontBufferLen)

        discard GetFontData(hdc, 0, 0, result.buffer, cast(DWORD) result.count)
        return result
    }

    // Creates or reuses a cached typeface from a borrowed Windows font handle.
    public func createFromHfont(fullname: string, hfont: HFONT)->*TypeFace fail
    {
        Sync.scopedLock(&lock)

        let str  = String.from(fullname)
        let here = g_HashTypeFace.tryFind(str)
        if here do
            return notnull here.value

        let tf = Memory.new'TypeFace()
        defer #fail Memory.delete(tf)
        tf.fullname = fullname
        tf.buffer   = readHfontData(hfont)

        let face = try Face.load(tf.buffer.toSlice())
        tf.face = notnull face

        g_HashTypeFace.add(str, tf)
        return tf
    }
}
