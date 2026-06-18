#global #if #os == Swag.TargetOs.Windows
#global public
using Swag, Core, Core.Errors, Win32, Gdi32

impl Image
{
    func fromBitmapHandle(hbitmap: HBITMAP)->Image throw
    {
        var result: retval

        var bitmap: BITMAP
        discard Gdi32Priv.GetObjectA(cast(HANDLE) hbitmap, #sizeof(BITMAP), &bitmap)

        switch bitmap.bmBitsPixel
        {
        case 24:
            result = create(bitmap.bmWidth, bitmap.bmHeight, PixelFormat.BGR8)
        case 32:
            result = create(bitmap.bmWidth, bitmap.bmHeight, PixelFormat.BGRA8)
        default:
            throw UnsupportedFormatError{"unsupported bit depth"}
        }

        let dc = GetDC(null)
        defer ReleaseDC(null, dc)

        var infos: BITMAPINFO
        infos.bmiHeader.biSize        = #sizeof(BITMAPINFOHEADER)
        infos.bmiHeader.biWidth       = bitmap.bmWidth
        infos.bmiHeader.biHeight      = bitmap.bmHeight
        infos.bmiHeader.biPlanes      = 1
        infos.bmiHeader.biBitCount    = bitmap.bmBitsPixel
        infos.bmiHeader.biCompression = BI_RGB
        GetDIBits(dc, hbitmap, 0, cast() bitmap.bmHeight, result.pixels.buffer, &infos, cast() DIB_RGB_COLORS)

        return result
    }

    // Transform an image to a windows icon
    mtd toHICON()->HICON throw
    {
        var bi: BITMAPINFO
        bi.bmiHeader.biSize        = #sizeof(BITMAPINFOHEADER)
        bi.bmiHeader.biWidth       = .width
        bi.bmiHeader.biHeight      = .height
        bi.bmiHeader.biPlanes      = 1
        bi.bmiHeader.biBitCount    = .bpp
        bi.bmiHeader.biCompression = BI_RGB

        var ppvBits: *u8
        let hbmp     = CreateDIBSection(null, &bi, cast() DIB_RGB_COLORS, &ppvBits, null, 0)
        defer #noerr DeleteObject(cast() hbmp)

        Memory.copy(ppvBits, .pixels.buffer, cast(u64) .width * .height * .bpp8)

        // CreateIconIndirect requires a non-null mask: for a 32-bit color icon the
        // alpha channel drives transparency, but the AND mask (hbmMask) must still
        // be supplied or the call fails and returns null. Reusing the color bitmap
        // as the mask is the standard trick for alpha icons.
        var ii: ICONINFO
        ii.fIcon    = TRUE
        ii.hbmMask  = hbmp
        ii.hbmColor = hbmp
        return CreateIconIndirect(&ii)
    }

    // Creates an image from a windows HICON
    func from(hicon: HICON)->Image throw
    {
        var result: retval
        var ii:     ICONINFO

        GetIconInfo(hicon, &ii)
        result = fromBitmapHandle(ii.hbmColor)

        if ii.hbmMask != null do
            DeleteObject(cast() ii.hbmMask)
        if ii.hbmColor != null do
            DeleteObject(cast() ii.hbmColor)

        return result
    }

    // Creates an image from a windows HBITMAP
    func from(hbitmap: HBITMAP)->Image throw
    {
        return fromBitmapHandle(hbitmap)
    }
}
