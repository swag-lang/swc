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

#[Swag.TestTag("integration.native")]
#test
{
    const Template = "/tmp/swag-linux-directory-XXXXXX"
    var temporary: [128] u8
    for byte, index in Template do
        temporary[index] = byte
    let created = mkdtemp(temporary.buffer)
    Swag.assert(created == temporary.buffer)
    defer discard unlinkat(AT_FDCWD, temporary.buffer, AT_REMOVEDIR)
    let directory = openat(AT_FDCWD, temporary.buffer, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    Swag.assert(directory >= 0)
    defer discard close(directory)

    const Child = "child?\\name"
    let made = mkdirat(directory, Child.buffer, 0x1C0)
    Swag.assert(made == 0)
    defer discard unlinkat(directory, Child.buffer, AT_REMOVEDIR)
    let duplicate      = mkdirat(directory, Child.buffer, 0x1C0)
    let duplicateError = errno()
    Swag.assert(duplicate == -1 and duplicateError == EEXIST)

    var info: stat
    let queried = fstatat(directory, Child.buffer, &info, 0)
    Swag.assert(queried == 0 and (info.st_mode & S_IFMT) == S_IFDIR)
    let linked = symlinkat(Child.buffer, directory, "link".buffer)
    Swag.assert(linked == 0)
    defer discard unlinkat(directory, "link".buffer, 0)
    let linkInfo = fstatat(directory, "link".buffer, &info, AT_SYMLINK_NOFOLLOW)
    Swag.assert(linkInfo == 0 and (info.st_mode & S_IFMT) == S_IFLNK)
    let targetInfo = fstatat(directory, "link".buffer, &info, 0)
    Swag.assert(targetInfo == 0 and (info.st_mode & S_IFMT) == S_IFDIR)
    let nonEmpty      = unlinkat(AT_FDCWD, temporary.buffer, AT_REMOVEDIR)
    let nonEmptyError = errno()
    Swag.assert(nonEmpty == -1 and nonEmptyError == ENOTEMPTY)

    let stream = unwrap opendir(temporary.buffer)
    defer discard closedir(stream)
    var childSeen, linkSeen = false
    for
    {
        errno(0)
        let entry = readdir(stream)
        if not entry
        {
            let error = errno()
            Swag.assert(error == 0)
            break
        }

        let name    = cast(string, cast(cstring, &entry.d_name[0]))
        var metadata: Structs.statx
        let queried = statx(directory, &entry.d_name[0], AT_SYMLINK_NOFOLLOW, STATX_BASIC_STATS | STATX_BTIME, &metadata)
        Swag.assert(queried == 0)
        if name == Child
        {
            childSeen = true
            Swag.assert((metadata.stx_mode & S_IFMT) == S_IFDIR)
        }
        elif name == "link"
        {
            linkSeen = true
            Swag.assert((metadata.stx_mode & S_IFMT) == S_IFLNK)
        }
    }

    Swag.assert(childSeen and linkSeen)

    var tiny: [1] u8
    let tooSmall = getcwd(tiny.buffer, tiny.count)
    let cwdError = errno()
    Swag.assert(tooSmall == null and cwdError == ERANGE)
    var current: [4096] u8
    let currentPath = getcwd(current.buffer, current.count)
    Swag.assert(currentPath == current.buffer and current[0] == '/')

    // A failing chdir leaves the process directory unchanged for the other tests.
    let invalidDirectory = chdir("".buffer)
    let changeError      = errno()
    Swag.assert(invalidDirectory == -1 and changeError == ENOENT)
}

#[Swag.TestTag("integration.native")]
#test
{
    const Template = "/tmp/swag-linux-mutation-XXXXXX"
    var temporary: [128] u8
    for byte, index in Template do
        temporary[index] = byte
    let created = mkdtemp(temporary.buffer)
    Swag.assert(created == temporary.buffer)
    defer discard unlinkat(AT_FDCWD, temporary.buffer, AT_REMOVEDIR)
    let directory = openat(AT_FDCWD, temporary.buffer, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    Swag.assert(directory >= 0)
    defer discard close(directory)
    let source = openat(directory, "source".buffer, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, 0x180'u32)
    Swag.assert(source >= 0)
    defer discard close(source)
    defer discard unlinkat(directory, "source".buffer, 0)
    let destination = openat(directory, "destination".buffer, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0x180'u32)
    Swag.assert(destination >= 0)
    defer discard close(destination)
    defer discard unlinkat(directory, "destination".buffer, 0)
    let written = write(source, "abc".buffer, 3)
    Swag.assert(written == 3)
    var info: stat
    let queried = fstat(source, &info)
    Swag.assert(queried == 0)
    let inode = info.st_ino
    let moved = renameat(directory, "source".buffer, directory, "destination".buffer)
    Swag.assert(moved == 0)
    let replaced = fstatat(directory, "destination".buffer, &info, 0)
    Swag.assert(replaced == 0 and info.st_ino == inode and info.st_size == 3)
    let absent       = fstatat(directory, "source".buffer, &info, 0)
    let missingError = errno()
    Swag.assert(absent == -1 and missingError == ENOENT)

    let initial: [2] timespec = [{tv_sec: 1_234_567_890, tv_nsec: 123_000_000}, {}]
    let reset = utimensat(directory, "destination".buffer, initial.buffer, 0)
    Swag.assert(reset == 0)
    let update: [2] timespec = [{tv_nsec: UTIME_OMIT}, {tv_nsec: UTIME_NOW}]
    let touched = utimensat(directory, "destination".buffer, update.buffer, 0)
    Swag.assert(touched == 0)
    let metadata = fstatat(directory, "destination".buffer, &info, 0)
    Swag.assert(metadata == 0 and info.st_atim.tv_sec == 1_234_567_890 and info.st_atim.tv_nsec == 123_000_000)
    Swag.assert(info.st_mtim.tv_sec > 0)
    let removed = unlinkat(directory, "destination".buffer, 0)
    Swag.assert(removed == 0)

    // Unlinking the path does not invalidate an already open file descriptor.
    let retained = fstat(source, &info)
    Swag.assert(retained == 0 and info.st_nlink == 0 and info.st_size == 3)
}

#[Swag.TestTag("integration.native")]
#test
{
    var start: timespec
    let sampled = clock_gettime(CLOCK_MONOTONIC, &start)
    Swag.assert(sampled == 0)
    var deadline = start
    deadline.tv_nsec += 2_000_000
    if deadline.tv_nsec >= 1_000_000_000
    {
        deadline.tv_nsec -= 1_000_000_000
        deadline.tv_sec  += 1
    }

    for
    {
        let error = clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &deadline, null)
        if error == EINTR do
            continue
        Swag.assert(error == 0)
        break
    }

    var finish: timespec
    let measured = clock_gettime(CLOCK_MONOTONIC, &finish)
    Swag.assert(measured == 0)
    Swag.assert(finish.tv_sec > deadline.tv_sec or finish.tv_sec == deadline.tv_sec and finish.tv_nsec >= deadline.tv_nsec)
    let invalid = timespec{tv_nsec: 1_000_000_000}
    let error   = clock_nanosleep(CLOCK_MONOTONIC, 0, &invalid, null)
    Swag.assert(error == EINVAL)
    let yielded = sched_yield()
    Swag.assert(yielded == 0)
    let terminal      = isatty(-1)
    let terminalError = errno()
    Swag.assert(terminal == 0 and terminalError == EBADF)
    let emptyName = getenv("".buffer)
    Swag.assert(emptyName == null)
    Swag.assert(getpid() > 0)
}

#[Swag.TestTag("integration.native")]
#test
{
    let descriptor = memfd_create("swag-statx-layout".buffer, MFD_CLOEXEC)
    Swag.assert(descriptor >= 0)
    defer discard close(descriptor)
    const LargeSize = 4_294_967_297's64
    let resized = ftruncate(descriptor, LargeSize)
    Swag.assert(resized == 0)
    var guarded: { before: u64, info: Structs.statx, after: u64 }
    guarded.before = 0x123456789ABCDEF0
    guarded.after  = 0xFEDCBA9876543210
    let queried = statx(descriptor, "".buffer, AT_EMPTY_PATH, STATX_BASIC_STATS | STATX_BTIME, &guarded.info)
    Swag.assert(queried == 0)
    Swag.assert(guarded.before == 0x123456789ABCDEF0 and guarded.after == 0xFEDCBA9876543210)
    Swag.assert(guarded.info.stx_size == cast(u64, LargeSize))
    Swag.assert((guarded.info.stx_mode & S_IFMT) == S_IFREG)
    Swag.assert((guarded.info.stx_mask & STATX_BASIC_STATS) == STATX_BASIC_STATS)
    var ordinary: stat
    let compared = fstat(descriptor, &ordinary)
    Swag.assert(compared == 0 and ordinary.st_ino == guarded.info.stx_ino)
    Swag.assert(ordinary.st_atim.tv_sec == guarded.info.stx_atime.tv_sec and ordinary.st_atim.tv_nsec == guarded.info.stx_atime.tv_nsec)
    if guarded.info.stx_mask & STATX_BTIME do
        Swag.assert(guarded.info.stx_btime.tv_nsec < 1_000_000_000)
}

struct PthreadProbe
{
    mutex:    Swag.Mutex
    changed:  Swag.Condition
    id:       s32
    released: bool
    value:    u32
}

#[Swag.CallingConvention(.C)]
func pthreadProbeEntry(argument: *void?)->*void?
{
    let probe = cast(*PthreadProbe, unwrap argument)
    probe.mutex.lock()
    probe.id = gettid()
    probe.changed.wake()
    while not probe.released do
        probe.changed.wait(&probe.mutex)
    probe.mutex.unlock()
    probe.value = 73
    return argument
}

#[Swag.TestTag("integration.native")]
#test
{
    // The gate proves that a nonblocking join observes a live native callback. The final
    // join publishes its writes and returns the exact C pointer result.
    var probe:  PthreadProbe
    var thread: pthread_t
    let created = pthread_create(&thread, null, &pthreadProbeEntry, &probe)
    Swag.assert(created == 0)
    probe.mutex.lock()
    while probe.id == 0 do
        probe.changed.wait(&probe.mutex)
    probe.mutex.unlock()
    Swag.assert(probe.id > 0 and probe.id != gettid())
    let pending = pthread_tryjoin_np(thread, null)
    Swag.assert(pending == EBUSY)
    var policy:    s32
    var parameter: sched_param
    let queried = pthread_getschedparam(thread, &policy, &parameter)
    Swag.assert(queried == 0)
    let invalid = pthread_setschedparam(thread, -1, &parameter)
    Swag.assert(invalid == EINVAL)
    parameter.sched_priority = 0
    let normalized = pthread_setschedparam(thread, SCHED_OTHER, &parameter)
    Swag.assert(normalized == 0)
    probe.mutex.lock()
    probe.released = true
    probe.changed.wake()
    probe.mutex.unlock()
    var result: *void?
    let joined = pthread_join(thread, &result)
    Swag.assert(joined == 0 and result == &probe and probe.value == 73)
}

#[Swag.TestTag("integration.native")]
#test
{
    var first: *ifaddrs?
    let queried = getifaddrs(&first)
    Swag.assert(queried == 0)
    if first
    {
        defer freeifaddrs(unwrap first)
        var current = first
        while current
        {
            let adapter = current
            current = adapter.ifa_next
            let name = unwrap adapter.ifa_name
            Swag.assert(name[0] != 0)
            if adapter.ifa_addr
            {
                let address = adapter.ifa_addr
                if address.sa_family == AF_PACKET
                {
                    let packet = cast(const *sockaddr_ll, cast(const *void, address))
                    let index  = if_nametoindex(name)
                    Swag.assert(index != 0 and index == cast(u32, packet.sll_ifindex))
                }
            }
        }
    }

    var guarded: { before: u64, mask: [1024] u8, after: u64 }
    guarded.before = 0x123456789ABCDEF0
    guarded.after  = 0xFEDCBA9876543210
    let affinity = sched_getaffinity(0, #sizeof(guarded.mask), &guarded.mask[0])
    Swag.assert(affinity == 0)
    Swag.assert(guarded.before == 0x123456789ABCDEF0 and guarded.after == 0xFEDCBA9876543210)
    var hasProcessor = false
    for byte in guarded.mask where byte != 0 do
        hasProcessor = true
    Swag.assert(hasProcessor)
}

#[Swag.TestTag("integration.native")]
#test
{
    const Template = "/tmp/swag-linux-open-XXXXXX"
    var temporary: [128] u8
    for byte, index in Template do
        temporary[index] = byte
    let created = mkdtemp(temporary.buffer)
    Swag.assert(created == temporary.buffer)
    defer discard unlinkat(AT_FDCWD, temporary.buffer, AT_REMOVEDIR)
    let directory = openat(AT_FDCWD, temporary.buffer, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    Swag.assert(directory >= 0)
    defer discard close(directory)
    let original = openat(directory, "data".buffer, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOCTTY, 0x180'u32)
    Swag.assert(original >= 0)
    defer discard close(original)
    defer discard unlinkat(directory, "data".buffer, 0)
    let written = write(original, "abc".buffer, 3)
    Swag.assert(written == 3)
    let flags = fcntl(original, F_GETFD)
    Swag.assert(flags >= 0 and (flags & FD_CLOEXEC) != 0)
    let duplicate      = openat(directory, "data".buffer, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0x180'u32)
    let duplicateError = errno()
    Swag.assert(duplicate == -1 and duplicateError == EEXIST)
    var before: stat
    let preserved = fstat(original, &before)
    Swag.assert(preserved == 0 and before.st_size == 3 and (before.st_mode & 0x7F) == 0)
    let inherited = openat(directory, "data".buffer, O_RDONLY | O_NOCTTY)
    Swag.assert(inherited >= 0)
    defer discard close(inherited)
    let inheritedFlags = fcntl(inherited, F_GETFD)
    Swag.assert(inheritedFlags >= 0 and (inheritedFlags & FD_CLOEXEC) == 0)
    let truncated = openat(directory, "data".buffer, O_WRONLY | O_TRUNC | O_CLOEXEC)
    Swag.assert(truncated >= 0)
    defer discard close(truncated)
    var after: stat
    let observed = fstat(original, &after)
    Swag.assert(observed == 0 and after.st_size == 0 and after.st_ino == before.st_ino)
}

#[Swag.TestTag("integration.native")]
#test
{
    var guarded: { before: u64, entry: passwd, after: u64 }
    guarded.before = 0x123456789ABCDEF0
    guarded.after  = 0xFEDCBA9876543210
    var buffer: [16384] u8
    var found:  *passwd?
    let uid     = getuid()
    let queried = getpwuid_r(uid, &guarded.entry, buffer.buffer, buffer.count, &found)
    Swag.assert(queried == 0)
    Swag.assert(guarded.before == 0x123456789ABCDEF0 and guarded.after == 0xFEDCBA9876543210)
    if found
    {
        Swag.assert(found == &guarded.entry and guarded.entry.pw_uid == uid)
        let homeAddress   = cast(u64, guarded.entry.pw_dir)
        let bufferAddress = cast(u64, buffer.buffer)
        Swag.assert(homeAddress >= bufferAddress and homeAddress < bufferAddress + buffer.count)
        var small: [1] u8
        found = null
        let shortBuffer = getpwuid_r(uid, &guarded.entry, small.buffer, small.count, &found)
        Swag.assert(shortBuffer == ERANGE and found == null)
        Swag.assert(guarded.before == 0x123456789ABCDEF0 and guarded.after == 0xFEDCBA9876543210)
    }
}
