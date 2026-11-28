#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core, Win32.Gdi32

#[Swag.TestTag("fonts.descriptors")]
#test
{
    let bytes     = makeTypeFaceCollection(cast(u16, FW_SEMIBOLD))
    let allocator = unwrap (Swag.getContext().defaultAllocator orelse Swag.getContext().allocator)

    let regular = expect TypeFace.loadFaceForFamily(bytes.toSlice(), "Segoe UI", FW_REGULAR, false, allocator)
    defer regular.destroy()
    let defaultWeight = expect TypeFace.loadFaceForFamily(bytes.toSlice(), "Segoe UI", FW_DONTCARE, false, allocator)
    defer defaultWeight.destroy()
    let semiBold = expect TypeFace.loadFaceForFamily(bytes.toSlice(), "Segoe UI", FW_SEMIBOLD, false, allocator)
    defer semiBold.destroy()

    Swag.require(regular.familyName == semiBold.familyName)
    Swag.require(not regular.isBold() and not defaultWeight.isBold() and semiBold.isBold())

    let italicBytes = makeTypeFaceCollection(cast(u16, FW_BOLD), true)
    let italic      = expect TypeFace.loadFaceForFamily(italicBytes.toSlice(), "Segoe UI", FW_REGULAR, true, allocator)
    defer italic.destroy()
    Swag.require(italic.isBold() and italic.isItalic())
}
