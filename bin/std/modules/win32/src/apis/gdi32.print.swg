#global export
#global if #os == Swag.TargetOs.Windows
#global namespace Gdi32

struct DOCINFOW
{
    public
    {
        cbSize:       INT
        lpszDocName:  LPCWSTR
        lpszOutput:   LPCWSTR
        lpszDatatype: LPCWSTR
        fwType:       DWORD
    }
}

#[Swag.Foreign("Gdi32", callconv: Swag.CallConv.C), Swag.Discardable]
{
    func CreateDCW(driver, device, port: LPCWSTR, mode: const *DEVMODEW?)->HDC
    func StartDocW(dc: HDC, info: const *DOCINFOW)->s32
    func EndDoc(dc: HDC)->s32
    func AbortDoc(dc: HDC)->s32
    func StartPage(dc: HDC)->s32
    func EndPage(dc: HDC)->s32
    func StretchDIBits(dc: HDC, xDest, yDest, destWidth, destHeight, xSrc, ySrc, srcWidth, srcHeight: s32, bits: LPCVOID, info: const *BITMAPINFO, usage: UINT, rop: DWORD)->s32
}
