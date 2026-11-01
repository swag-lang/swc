#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#[Swag.TestTag("integration.native")]
#test
{
    let descriptor = openat(AT_FDCWD, "/dev/null".buffer, O_RDONLY | O_CLOEXEC)
    Swag.assert(descriptor >= 0)
    defer discard close(descriptor)

    var descriptors: [2] s32
    let created = pipe2(&descriptors[0], O_CLOEXEC)
    Swag.assert(created == 0)
    defer discard close(descriptors[0])
    defer discard close(descriptors[1])
    let written = write(descriptors[1], "abc".buffer, 3)
    Swag.assert(written == 3)
    var count   = -1's32
    let queried = ioctl(descriptors[0], FIONREAD, &count)
    Swag.assert(queried == 0 and count == 3)
}

#[Swag.TestTag("integration.native")]
#test
{
    let directory = opendir("/proc/self/fd".buffer)
    Swag.assert(directory != null)
    defer discard closedir(unwrap directory)
    let descriptor = dirfd(directory)
    Swag.assert(descriptor >= 0)
    let first = readdir(directory)
    Swag.assert(first != null)
    rewinddir(directory)
    let again = readdir(directory)
    Swag.assert(again != null)
}

#[Swag.TestTag("integration.native")]
#test
{
    let size       = cast(u64, getpagesize())
    let descriptor = memfd_create("swag-linux-bindings".buffer, MFD_CLOEXEC)
    Swag.assert(descriptor >= 0)
    defer discard close(descriptor)
    let resized = ftruncate(descriptor, cast(s64, size))
    Swag.assert(resized == 0)
    let view = mmap(null, size, PROT_READ | PROT_WRITE, MAP_PRIVATE, descriptor, 0)
    Swag.assert(cast(s64, view) != -1 and view != null)
    defer discard munmap(view, size)
    let bytes = Swag.makeSlice(cast([*] u8, view), size)
    bytes[0]        = 123
    bytes[size - 1] = 231

    // Reclaim may decline the hint (for example without swap), but must retain private data.
    discard madvise(view, size, MADV_PAGEOUT)
    Swag.assert(bytes[0] == 123 and bytes[size - 1] == 231)
}
