#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

// Page release must not discard anonymous bytes, including neighboring data on boundary pages.
#[Swag.TestTag("integration.memory")]
#test
{
    let size   = cast(u64, Linux.getpagesize()) * 3
    let memory = Linux.mmap(null, size, Linux.PROT_READ | Linux.PROT_WRITE, Linux.MAP_PRIVATE | Linux.MAP_ANONYMOUS, -1, 0)
    Swag.require(cast(s64, memory) != -1 and memory != null)
    defer discard Linux.munmap(memory, size)
    let bytes = Swag.makeSlice(cast([*] u8, memory), size)
    for &value, index in bytes do
        value[] = cast(u8, (index % 239))

    File.MappedRegion.releasePages(bytes[until 0])
    File.MappedRegion.releasePages(bytes[17 until size - 23])
    File.MappedRegion.releasePages(bytes)
    for value, index in bytes do
        Swag.require(value == cast(u8, (index % 239)))

    var stack: [512] u8
    stack[0]   = 19
    stack[511] = 73
    File.MappedRegion.releasePages(stack)
    Swag.require(stack[0] == 19 and stack[511] == 73)
}

// A private dirty mapping keeps its changes while the backing file remains unchanged.
#[Swag.TestTag("integration.memory")]
#test
{
    let descriptor = Linux.memfd_create("swag-core-release-pages".buffer, Linux.MFD_CLOEXEC)
    Swag.require(descriptor >= 0)
    defer discard Linux.close(descriptor)
    let size    = cast(u64, Linux.getpagesize()) * 2
    let resized = Linux.ftruncate(descriptor, cast(s64, size))
    Swag.require(resized == 0)

    let shared = Linux.mmap(null, size, Linux.PROT_READ | Linux.PROT_WRITE, Linux.MAP_SHARED, descriptor, 0)
    Swag.require(cast(s64, shared) != -1 and shared != null)
    defer discard Linux.munmap(shared, size)
    let original = Swag.makeSlice(cast([*] u8, shared), size)
    original[0]        = 31
    original[size - 1] = 47

    let view = Linux.mmap(null, size, Linux.PROT_READ | Linux.PROT_WRITE, Linux.MAP_PRIVATE, descriptor, 0)
    Swag.require(cast(s64, view) != -1 and view != null)
    defer discard Linux.munmap(view, size)
    let changed = Swag.makeSlice(cast([*] u8, view), size)
    Swag.require(changed[0] == 31 and changed[size - 1] == 47)
    changed[0]        = 99
    changed[size - 1] = 100
    File.MappedRegion.releasePages(changed[1 until size - 1])
    Swag.require(changed[0] == 99 and changed[size - 1] == 100)
    Swag.require(original[0] == 31 and original[size - 1] == 47)
}
