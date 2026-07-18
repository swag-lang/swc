#global #if #os == Swag.TargetOs.Windows
#global #[Swag.ExplicitNullability]
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
    public func createFromHFONT(fullname: #nonull string, hf: HFONT)->#nonull *TypeFace throw
    {
        Sync.scopedLock(&lock)

        let str  = String.from(fullname)
        let here = g_HashTypeFace.tryFind(str)
        if here do
            return here.value orelse cast(#nonull *TypeFace) 1'u64

        let tf = Memory.new'TypeFace()
        tf.fullname = fullname
        tf.buffer   = getDataFromHFONT(hf)

        tf.face = (try Face.load(tf.buffer.toSlice())) orelse cast(#nonull *Face) 1'u64

        g_HashTypeFace.add(str, tf)
        return tf
    }
}
