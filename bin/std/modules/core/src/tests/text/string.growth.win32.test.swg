#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Win32

// Growing an inline string must read only its old contents. The following native page
// remains reserved, so copying the new length out of the inline buffer faults.
#test
{
    let pages = cast([*] u8) VirtualAlloc(null, 8192, MEM_RESERVE, PAGE_READWRITE)!
    defer discard VirtualFree(pages, 0, MEM_RELEASE)
    let committed = VirtualAlloc(pages, 4096, MEM_COMMIT, PAGE_READWRITE)
    Swag.assert(committed != null)

    let value = cast(*String) (pages + 4096 - #sizeof(String))
    defer value.opDrop()
    value.opSet("small")
    let text = "this assignment grows beyond the inline buffer at the end of the committed page"
    value.opSet(text)
    Swag.assert(value.toString() == text)
}
