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

#[Swag.TestTag("integration.native")]
#test
{
    var bytes: [258] u8
    bytes[0]   = 17
    bytes[257] = 29
    let filled = getentropy(&bytes[1], 256)
    Swag.assert(filled == 0 and bytes[0] == 17 and bytes[257] == 29)
    explicit_bzero(&bytes[1], 256)
    for value in bytes[1 until 257] do
        Swag.assert(value == 0)
    Swag.assert(bytes[0] == 17 and bytes[257] == 29)

    let oversized = getentropy(&bytes[1], 257)
    Swag.assert(oversized == -1)
    Swag.assert(bytes[0] == 17 and bytes[257] == 29)
}

#[Swag.CallingConvention(.C)]
alias UnaryDouble = func(f64)->f64

#[Swag.TestTag("integration.native")]
#test
{
    let handle = dlopen("libm.so.6".buffer, RTLD_NOW | RTLD_LOCAL)
    Swag.assert(handle != null)
    defer discard dlclose(unwrap handle)
    let symbol = dlsym(handle, "cos".buffer)
    Swag.assert(symbol != null)
    let cosine = cast(UnaryDouble, symbol)
    let value  = cosine(0)
    Swag.assert(value == 1)

    discard dlerror()
    let absent      = dlsym(handle, "swag_missing_native_binding_symbol".buffer)
    let symbolError = dlerror()
    Swag.assert(absent == null and symbolError != null)
    let missing      = dlopen("/swag_missing_native_binding_library.so".buffer, RTLD_NOW)
    let libraryError = dlerror()
    Swag.assert(missing == null and libraryError != null)
}

#[Swag.TestTag("integration.native")]
#test
{
    var first, second: timespec
    let firstRead  = clock_gettime(CLOCK_MONOTONIC, &first)
    let secondRead = clock_gettime(CLOCK_MONOTONIC, &second)
    Swag.assert(firstRead == 0 and secondRead == 0)
    Swag.assert(second.tv_sec > first.tv_sec or (second.tv_sec == first.tv_sec and second.tv_nsec >= first.tv_nsec))
    Swag.assert(first.tv_nsec >= 0 and first.tv_nsec < 1_000_000_000)
    Swag.assert(second.tv_nsec >= 0 and second.tv_nsec < 1_000_000_000)

    var wall: timespec
    let wallRead = clock_gettime(CLOCK_REALTIME, &wall)
    Swag.assert(wallRead == 0 and wall.tv_sec > 0)
    Swag.assert(wall.tv_nsec >= 0 and wall.tv_nsec < 1_000_000_000)
}
