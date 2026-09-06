#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// The checked wrapper preserves HRESULT failures and writes the caller's output structure.
#test
{
    var info: SHSTOCKICONINFO
    catch SHGetStockIconInfo(.SIID_FOLDER, SHGSI_ICONLOCATION, &info) as badSize
    Swag.assert(badSize is SystemError)
    Swag.assert((cast(SystemError) badSize).errorID == 0x80070057'u32)

    info.cbSize = #sizeof(SHSTOCKICONINFO)
    expect SHGetStockIconInfo(.SIID_FOLDER, SHGSI_ICON | SHGSI_SMALLICON, &info)
    Swag.assert(info.hIcon != null)
    defer catch DestroyIcon(info.hIcon)
    Swag.assert(info.szPath[0] != 0)
}
