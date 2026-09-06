#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Win32

#[Foreign("kernel32", callconv: Swag.CallConv.C)]
func SetLastError(errorCode: DWORD)

// A missing font table returns GDI_ERROR without necessarily setting a last-error code.
#test
{
    let dc = expect CreateCompatibleDC(null)
    defer catch DeleteDC(dc)
    SetLastError(0)
    discard catch GetFontData(dc, 0x3F3F3F3F, 0, null, 0) as missingTable
    Swag.assert(missingTable is SystemError)
}
