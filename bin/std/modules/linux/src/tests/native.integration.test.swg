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

#[Swag.TestTag("integration.native")]
#test
{
    // UTC conversion must preserve negative epochs, the leap day and post-2038 dates.
    for seconds in [-1's64, 0, 951_827_696, 1_719_792_000, 2_208_988_800]
    {
        var universal: tm
        let utcResult = gmtime_r(&seconds, &universal)
        Swag.assert(utcResult == &universal)
        let roundTrip = timegm(&universal)
        Swag.assert(roundTrip == seconds)
        if seconds == -1 do
            Swag.assert(universal.tm_year == 69 and
                        universal.tm_mon == 11 and
                        universal.tm_mday == 31 and
                        universal.tm_sec == 59)
        if seconds == 951_827_696 do
            Swag.assert(universal.tm_year == 100 and universal.tm_mon == 1 and universal.tm_mday == 29)

        var local: tm
        let localResult = localtime_r(&seconds, &local)
        Swag.assert(localResult == &local)
        let localRoundTrip = mktime(&local)
        Swag.assert(localRoundTrip == seconds)
        let offset = local.tm_gmtoff
        let asUtc  = timegm(&local)
        Swag.assert(asUtc == seconds + offset)
    }
}

#[Swag.TestTag("integration.native")]
#test
{
    let descriptor = memfd_create("swag-stream-bindings".buffer, MFD_CLOEXEC)
    Swag.assert(descriptor >= 0)
    defer discard close(descriptor)

    const LargeOffset = 4_294_967_297's64
    let resized = ftruncate(descriptor, LargeOffset)
    Swag.assert(resized == 0)
    let sought = lseek(descriptor, LargeOffset, SEEK_SET)
    Swag.assert(sought == LargeOffset)
    let written = write(descriptor, "abc".buffer, 3)
    Swag.assert(written == 3)
    let flushed = fsync(descriptor)
    Swag.assert(flushed == 0)

    var guarded: { before: u64, info: stat, after: u64 }
    guarded.before = 0x123456789ABCDEF0
    guarded.after  = 0xFEDCBA9876543210
    let queried = fstat(descriptor, &guarded.info)
    Swag.assert(queried == 0 and guarded.info.st_size == LargeOffset + 3)
    Swag.assert((guarded.info.st_mode & S_IFMT) == S_IFREG)
    Swag.assert(guarded.before == 0x123456789ABCDEF0 and guarded.after == 0xFEDCBA9876543210)

    let rewound = lseek(descriptor, -3, SEEK_END)
    Swag.assert(rewound == LargeOffset)
    var bytes: [4] u8
    bytes[3] = 57
    let count = read(descriptor, &bytes[0], bytes.count)
    Swag.assert(count == 3 and bytes[0] == 'a' and bytes[1] == 'b' and bytes[2] == 'c' and bytes[3] == 57)
    let eof = read(descriptor, &bytes[0], 1)
    Swag.assert(eof == 0)
    let truncated = ftruncate(descriptor, 2)
    Swag.assert(truncated == 0)
    let position = lseek(descriptor, 0, SEEK_CUR)
    Swag.assert(position == LargeOffset + 3)

    let directory = fstatat(AT_FDCWD, ".".buffer, &guarded.info, 0)
    Swag.assert(directory == 0 and (guarded.info.st_mode & S_IFMT) == S_IFDIR)
    errno(0)
    let invalid = fstat(-1, &guarded.info)
    let error   = errno()
    Swag.assert(invalid == -1 and error == EBADF)
    let message = cast(string, cast(cstring, strerror(error)))
    Swag.assert(message.count > 0)
}

#[Swag.TestTag("integration.native")]
#test
{
    var descriptor = memfd_create("swag-map-ownership".buffer, MFD_CLOEXEC)
    Swag.assert(descriptor >= 0)
    defer if descriptor >= 0 do
        discard close(descriptor)
    let length  = cast(u64, getpagesize()) * 2
    let resized = ftruncate(descriptor, cast(s64, length))
    Swag.assert(resized == 0)
    let duplicate = fcntl(descriptor, F_DUPFD_CLOEXEC, 0's32)
    Swag.assert(duplicate >= 0 and duplicate != descriptor)
    defer discard close(duplicate)
    let flags = fcntl(duplicate, F_GETFD)
    Swag.assert(flags >= 0 and (flags & FD_CLOEXEC) != 0)

    let view = mmap(null, length, PROT_READ | PROT_WRITE, MAP_SHARED, duplicate, 0)
    Swag.assert(cast(s64, view) != -1 and view != null)
    defer discard munmap(view, length)
    let closed = close(descriptor)
    descriptor = -1
    Swag.assert(closed == 0)
    let bytes = Swag.makeSlice(cast([*] u8, view), length)
    bytes[17]         = 91
    bytes[length - 1] = 83
    let synced = msync(view, length, MS_SYNC)
    Swag.assert(synced == 0)
    let flushed = fsync(duplicate)
    Swag.assert(flushed == 0)
    let sought = lseek(duplicate, 17, SEEK_SET)
    Swag.assert(sought == 17)
    var value: u8
    let count = read(duplicate, &value, 1)
    Swag.assert(count == 1 and value == 91)
    Swag.assert(bytes[length - 1] == 83)
}
