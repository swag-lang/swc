#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

#[Swag.Foreign("kernel32", "VirtualAlloc")]
func allocateStringGuard(address: *void?, size: u64, allocationType, protection: u32)->[*] u8?

#[Swag.Foreign("kernel32", "VirtualFree")]
func releaseStringGuard(address: *void?, size: u64, freeType: u32)->s32

// Growing an inline string must read only its old contents. The following page
// remains reserved, so copying the new length out of the inline buffer faults.
#test
{
    let pages = allocateStringGuard(null, 8192, 0x2000, 0x04)!
    defer discard releaseStringGuard(pages, 0, 0x8000)
    Swag.assert(allocateStringGuard(pages, 4096, 0x1000, 0x04) != null)

    let value = cast(*String) (pages + 4096 - #sizeof(String))
    defer value.opDrop()
    value.opSet("small")
    let text = "this assignment grows beyond the inline buffer at the end of the committed page"
    value.opSet(text)
    Swag.assert(value.toString() == text)
}
