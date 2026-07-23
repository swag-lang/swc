#global #if #os == Swag.TargetOs.Windows

using Core, Win32, Gdi32, TrueType

impl TypeFace
{
    func getDataFromHFONT(hf: HFONT)->Array'u8 throw
    {
        var result: retval

        let hdc = GetDC(null)
        defer ReleaseDC(null, hdc)

        SelectObject(hdc, cast() hf)
        defer catch DeleteObject(cast() hf)

        let outFontBufferLen = GetFontData(hdc, 0, 0, null, 0)
        result.resize(cast() outFontBufferLen)

        discard GetFontData(hdc, 0, 0, result.buffer, cast(DWORD) result.count)
        return result
    }

    // Create a new typeface from a HFONT
    public func createFromHFONT(fullname: string, hf: HFONT)->*TypeFace throw
    {
        Sync.scopedLock(&lock)

        let str  = String.from(fullname)
        let here = g_HashTypeFace.tryFind(str)
        if here do
            return notnull here.value

        let tf = Memory.new'TypeFace()
        tf.fullname = fullname
        tf.buffer   = getDataFromHFONT(hf)

        let face = try Face.load(tf.buffer.toSlice())
        tf.face = notnull face

        g_HashTypeFace.add(str, tf)
        return tf
    }
}
