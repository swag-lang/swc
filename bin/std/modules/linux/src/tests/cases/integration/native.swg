#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#[Swag.TestTag("integration.native")]
#test
{
    let descriptor = openat(AT_FDCWD, "/dev/null".buffer, O_RDONLY | O_CLOEXEC)
    Swag.require(descriptor >= 0)
    defer discard close(descriptor)

    var descriptors: [2] s32
    let created = pipe2(&descriptors[0], O_CLOEXEC)
    Swag.require(created == 0)
    defer discard close(descriptors[0])
    defer discard close(descriptors[1])
    let written = write(descriptors[1], "abc".buffer, 3)
    Swag.require(written == 3)
    var count   = -1's32
    let queried = ioctl(descriptors[0], FIONREAD, &count)
    Swag.require(queried == 0 and count == 3)
}

#[Swag.TestTag("integration.native")]
#test
{
    let directory = opendir("/proc/self/fd".buffer)
    Swag.require(directory != null)
    defer discard closedir(unwrap directory)
    let descriptor = dirfd(directory)
    Swag.require(descriptor >= 0)
    let first = readdir(directory)
    Swag.require(first != null)
    rewinddir(directory)
    let again = readdir(directory)
    Swag.require(again != null)
}

#[Swag.TestTag("integration.native")]
#test
{
    let size       = cast(u64, getpagesize())
    let descriptor = memfd_create("swag-linux-bindings".buffer, MFD_CLOEXEC)
    Swag.require(descriptor >= 0)
    defer discard close(descriptor)
    let resized = ftruncate(descriptor, cast(s64, size))
    Swag.require(resized == 0)
    let view = mmap(null, size, PROT_READ | PROT_WRITE, MAP_PRIVATE, descriptor, 0)
    Swag.require(cast(s64, view) != -1 and view != null)
    defer discard munmap(view, size)
    let bytes = Swag.makeSlice(cast([*] u8, view), size)
    bytes[0]        = 123
    bytes[size - 1] = 231

    // Reclaim may decline the hint (for example without swap), but must retain private data.
    discard madvise(view, size, MADV_PAGEOUT)
    Swag.require(bytes[0] == 123 and bytes[size - 1] == 231)
}

#[Swag.TestTag("integration.native")]
#test
{
    var bytes: [258] u8
    bytes[0]   = 17
    bytes[257] = 29
    let filled = getentropy(&bytes[1], 256)
    Swag.require(filled == 0 and bytes[0] == 17 and bytes[257] == 29)
    explicit_bzero(&bytes[1], 256)
    for value in bytes[1 until 257] do
        Swag.require(value == 0)
    Swag.require(bytes[0] == 17 and bytes[257] == 29)

    let oversized = getentropy(&bytes[1], 257)
    Swag.require(oversized == -1)
    Swag.require(bytes[0] == 17 and bytes[257] == 29)
}

#[Swag.CallingConvention(.C)]
alias UnaryDouble = func(f64)->f64

#[Swag.TestTag("integration.native")]
#test
{
    let handle = dlopen("libm.so.6".buffer, RTLD_NOW | RTLD_LOCAL)
    Swag.require(handle != null)
    defer discard dlclose(unwrap handle)
    let symbol = dlsym(handle, "cos".buffer)
    Swag.require(symbol != null)
    let cosine = cast(UnaryDouble, symbol)
    let value  = cosine(0)
    Swag.require(value == 1)

    discard dlerror()
    let absent      = dlsym(handle, "swag_missing_native_binding_symbol".buffer)
    let symbolError = dlerror()
    Swag.require(absent == null and symbolError != null)
    let missing      = dlopen("/swag_missing_native_binding_library.so".buffer, RTLD_NOW)
    let libraryError = dlerror()
    Swag.require(missing == null and libraryError != null)
}

#[Swag.TestTag("integration.native")]
#test
{
    var first, second: timespec
    let firstRead  = clock_gettime(CLOCK_MONOTONIC, &first)
    let secondRead = clock_gettime(CLOCK_MONOTONIC, &second)
    Swag.require(firstRead == 0 and secondRead == 0)
    Swag.require(second.tv_sec > first.tv_sec or (second.tv_sec == first.tv_sec and second.tv_nsec >= first.tv_nsec))
    Swag.require(first.tv_nsec >= 0 and first.tv_nsec < 1_000_000_000)
    Swag.require(second.tv_nsec >= 0 and second.tv_nsec < 1_000_000_000)

    var wall: timespec
    let wallRead = clock_gettime(CLOCK_REALTIME, &wall)
    Swag.require(wallRead == 0 and wall.tv_sec > 0)
    Swag.require(wall.tv_nsec >= 0 and wall.tv_nsec < 1_000_000_000)
}

#[Swag.TestTag("integration.native")]
#test
{
    // UTC conversion must preserve negative epochs, the leap day and post-2038 dates.
    for seconds in [-1's64, 0, 951_827_696, 1_719_792_000, 2_208_988_800]
    {
        var universal: tm
        let utcResult = gmtime_r(&seconds, &universal)
        Swag.require(utcResult == &universal)
        let roundTrip = timegm(&universal)
        Swag.require(roundTrip == seconds)
        if seconds == -1 do
            Swag.require(universal.tm_year == 69 and
                        universal.tm_mon == 11 and
                        universal.tm_mday == 31 and
                        universal.tm_sec == 59)
        if seconds == 951_827_696 do
            Swag.require(universal.tm_year == 100 and universal.tm_mon == 1 and universal.tm_mday == 29)

        var local: tm
        let localResult = localtime_r(&seconds, &local)
        Swag.require(localResult == &local)
        let localRoundTrip = mktime(&local)
        Swag.require(localRoundTrip == seconds)
        let offset = local.tm_gmtoff
        let asUtc  = timegm(&local)
        Swag.require(asUtc == seconds + offset)
    }
}

#[Swag.TestTag("integration.native")]
#test
{
    let descriptor = memfd_create("swag-stream-bindings".buffer, MFD_CLOEXEC)
    Swag.require(descriptor >= 0)
    defer discard close(descriptor)

    const LargeOffset = 4_294_967_297's64
    let resized = ftruncate(descriptor, LargeOffset)
    Swag.require(resized == 0)
    let sought = lseek(descriptor, LargeOffset, SEEK_SET)
    Swag.require(sought == LargeOffset)
    let written = write(descriptor, "abc".buffer, 3)
    Swag.require(written == 3)
    let flushed = fsync(descriptor)
    Swag.require(flushed == 0)

    var guarded: { before: u64, info: stat, after: u64 }
    guarded.before = 0x123456789ABCDEF0
    guarded.after  = 0xFEDCBA9876543210
    let queried = fstat(descriptor, &guarded.info)
    Swag.require(queried == 0 and guarded.info.st_size == LargeOffset + 3)
    Swag.require((guarded.info.st_mode & S_IFMT) == S_IFREG)
    Swag.require(guarded.before == 0x123456789ABCDEF0 and guarded.after == 0xFEDCBA9876543210)

    let rewound = lseek(descriptor, -3, SEEK_END)
    Swag.require(rewound == LargeOffset)
    var bytes: [4] u8
    bytes[3] = 57
    let count = read(descriptor, &bytes[0], bytes.count)
    Swag.require(count == 3 and bytes[0] == 'a' and bytes[1] == 'b' and bytes[2] == 'c' and bytes[3] == 57)
    let eof = read(descriptor, &bytes[0], 1)
    Swag.require(eof == 0)
    let truncated = ftruncate(descriptor, 2)
    Swag.require(truncated == 0)
    let position = lseek(descriptor, 0, SEEK_CUR)
    Swag.require(position == LargeOffset + 3)

    let directory = fstatat(AT_FDCWD, ".".buffer, &guarded.info, 0)
    Swag.require(directory == 0 and (guarded.info.st_mode & S_IFMT) == S_IFDIR)
    errno(0)
    let invalid = fstat(-1, &guarded.info)
    let error   = errno()
    Swag.require(invalid == -1 and error == EBADF)
    let message = cast(string, cast(cstring, strerror(error)))
    Swag.require(message.count > 0)
}

#[Swag.TestTag("integration.native")]
#test
{
    var descriptor = memfd_create("swag-map-ownership".buffer, MFD_CLOEXEC)
    Swag.require(descriptor >= 0)
    defer if descriptor >= 0 do
        discard close(descriptor)
    let length  = cast(u64, getpagesize()) * 2
    let resized = ftruncate(descriptor, cast(s64, length))
    Swag.require(resized == 0)
    let duplicate = fcntl(descriptor, F_DUPFD_CLOEXEC, 0's32)
    Swag.require(duplicate >= 0 and duplicate != descriptor)
    defer discard close(duplicate)
    let flags = fcntl(duplicate, F_GETFD)
    Swag.require(flags >= 0 and (flags & FD_CLOEXEC) != 0)

    let view = mmap(null, length, PROT_READ | PROT_WRITE, MAP_SHARED, duplicate, 0)
    Swag.require(cast(s64, view) != -1 and view != null)
    defer discard munmap(view, length)
    let closed = close(descriptor)
    descriptor = -1
    Swag.require(closed == 0)
    let bytes = Swag.makeSlice(cast([*] u8, view), length)
    bytes[17]         = 91
    bytes[length - 1] = 83
    let synced = msync(view, length, MS_SYNC)
    Swag.require(synced == 0)
    let flushed = fsync(duplicate)
    Swag.require(flushed == 0)
    let sought = lseek(duplicate, 17, SEEK_SET)
    Swag.require(sought == 17)
    var value: u8
    let count = read(duplicate, &value, 1)
    Swag.require(count == 1 and value == 91)
    Swag.require(bytes[length - 1] == 83)
}

#[Swag.TestTag("integration.native")]
#test
{
    const Template = "/tmp/swag-linux-directory-XXXXXX"
    var temporary: [128] u8
    for byte, index in Template do
        temporary[index] = byte
    let created = mkdtemp(temporary.buffer)
    Swag.require(created == temporary.buffer)
    defer discard unlinkat(AT_FDCWD, temporary.buffer, AT_REMOVEDIR)
    let directory = openat(AT_FDCWD, temporary.buffer, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    Swag.require(directory >= 0)
    defer discard close(directory)

    const Child = "child?\\name"
    let made = mkdirat(directory, Child.buffer, 0x1C0)
    Swag.require(made == 0)
    defer discard unlinkat(directory, Child.buffer, AT_REMOVEDIR)
    let duplicate      = mkdirat(directory, Child.buffer, 0x1C0)
    let duplicateError = errno()
    Swag.require(duplicate == -1 and duplicateError == EEXIST)

    var info: stat
    let queried = fstatat(directory, Child.buffer, &info, 0)
    Swag.require(queried == 0 and (info.st_mode & S_IFMT) == S_IFDIR)
    let linked = symlinkat(Child.buffer, directory, "link".buffer)
    Swag.require(linked == 0)
    defer discard unlinkat(directory, "link".buffer, 0)
    let linkInfo = fstatat(directory, "link".buffer, &info, AT_SYMLINK_NOFOLLOW)
    Swag.require(linkInfo == 0 and (info.st_mode & S_IFMT) == S_IFLNK)
    let targetInfo = fstatat(directory, "link".buffer, &info, 0)
    Swag.require(targetInfo == 0 and (info.st_mode & S_IFMT) == S_IFDIR)
    let nonEmpty      = unlinkat(AT_FDCWD, temporary.buffer, AT_REMOVEDIR)
    let nonEmptyError = errno()
    Swag.require(nonEmpty == -1 and nonEmptyError == ENOTEMPTY)

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
            Swag.require(error == 0)
            break
        }

        let name    = cast(string, cast(cstring, &entry.d_name[0]))
        var metadata: Structs.statx
        let queried = statx(directory, &entry.d_name[0], AT_SYMLINK_NOFOLLOW, STATX_BASIC_STATS | STATX_BTIME, &metadata)
        Swag.require(queried == 0)
        if name == Child
        {
            childSeen = true
            Swag.require((metadata.stx_mode & S_IFMT) == S_IFDIR)
        }
        elif name == "link"
        {
            linkSeen = true
            Swag.require((metadata.stx_mode & S_IFMT) == S_IFLNK)
        }
    }

    Swag.require(childSeen and linkSeen)

    var tiny: [1] u8
    let tooSmall = getcwd(tiny.buffer, tiny.count)
    let cwdError = errno()
    Swag.require(tooSmall == null and cwdError == ERANGE)
    var current: [4096] u8
    let currentPath = getcwd(current.buffer, current.count)
    Swag.require(currentPath == current.buffer and current[0] == '/')

    // A failing chdir leaves the process directory unchanged for the other tests.
    let invalidDirectory = chdir("".buffer)
    let changeError      = errno()
    Swag.require(invalidDirectory == -1 and changeError == ENOENT)
}

#[Swag.TestTag("integration.native")]
#test
{
    const Template = "/tmp/swag-linux-mutation-XXXXXX"
    var temporary: [128] u8
    for byte, index in Template do
        temporary[index] = byte
    let created = mkdtemp(temporary.buffer)
    Swag.require(created == temporary.buffer)
    defer discard unlinkat(AT_FDCWD, temporary.buffer, AT_REMOVEDIR)
    let directory = openat(AT_FDCWD, temporary.buffer, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    Swag.require(directory >= 0)
    defer discard close(directory)
    let source = openat(directory, "source".buffer, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, 0x180'u32)
    Swag.require(source >= 0)
    defer discard close(source)
    defer discard unlinkat(directory, "source".buffer, 0)
    let destination = openat(directory, "destination".buffer, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0x180'u32)
    Swag.require(destination >= 0)
    defer discard close(destination)
    defer discard unlinkat(directory, "destination".buffer, 0)
    let written = write(source, "abc".buffer, 3)
    Swag.require(written == 3)
    var info: stat
    let queried = fstat(source, &info)
    Swag.require(queried == 0)
    let inode = info.st_ino
    let moved = renameat(directory, "source".buffer, directory, "destination".buffer)
    Swag.require(moved == 0)
    let replaced = fstatat(directory, "destination".buffer, &info, 0)
    Swag.require(replaced == 0 and info.st_ino == inode and info.st_size == 3)
    let absent       = fstatat(directory, "source".buffer, &info, 0)
    let missingError = errno()
    Swag.require(absent == -1 and missingError == ENOENT)

    let initial: [2] timespec = [{tv_sec: 1_234_567_890, tv_nsec: 123_000_000}, {}]
    let reset = utimensat(directory, "destination".buffer, initial.buffer, 0)
    Swag.require(reset == 0)
    let update: [2] timespec = [{tv_nsec: UTIME_OMIT}, {tv_nsec: UTIME_NOW}]
    let touched = utimensat(directory, "destination".buffer, update.buffer, 0)
    Swag.require(touched == 0)
    let metadata = fstatat(directory, "destination".buffer, &info, 0)
    Swag.require(metadata == 0 and info.st_atim.tv_sec == 1_234_567_890 and info.st_atim.tv_nsec == 123_000_000)
    Swag.require(info.st_mtim.tv_sec > 0)
    let removed = unlinkat(directory, "destination".buffer, 0)
    Swag.require(removed == 0)

    // Unlinking the path does not invalidate an already open file descriptor.
    let retained = fstat(source, &info)
    Swag.require(retained == 0 and info.st_nlink == 0 and info.st_size == 3)
}

#[Swag.TestTag("integration.native")]
#test
{
    var start: timespec
    let sampled = clock_gettime(CLOCK_MONOTONIC, &start)
    Swag.require(sampled == 0)
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
        Swag.require(error == 0)
        break
    }

    var finish: timespec
    let measured = clock_gettime(CLOCK_MONOTONIC, &finish)
    Swag.require(measured == 0)
    Swag.require(finish.tv_sec > deadline.tv_sec or finish.tv_sec == deadline.tv_sec and finish.tv_nsec >= deadline.tv_nsec)
    let invalid = timespec{tv_nsec: 1_000_000_000}
    let error   = clock_nanosleep(CLOCK_MONOTONIC, 0, &invalid, null)
    Swag.require(error == EINVAL)
    let yielded = sched_yield()
    Swag.require(yielded == 0)
    let terminal      = isatty(-1)
    let terminalError = errno()
    Swag.require(terminal == 0 and terminalError == EBADF)
    let emptyName = getenv("".buffer)
    Swag.require(emptyName == null)
    Swag.require(getpid() > 0)
}

#[Swag.TestTag("integration.native")]
#test
{
    let descriptor = memfd_create("swag-statx-layout".buffer, MFD_CLOEXEC)
    Swag.require(descriptor >= 0)
    defer discard close(descriptor)
    const LargeSize = 4_294_967_297's64
    let resized = ftruncate(descriptor, LargeSize)
    Swag.require(resized == 0)
    var guarded: { before: u64, info: Structs.statx, after: u64 }
    guarded.before = 0x123456789ABCDEF0
    guarded.after  = 0xFEDCBA9876543210
    let queried = statx(descriptor, "".buffer, AT_EMPTY_PATH, STATX_BASIC_STATS | STATX_BTIME, &guarded.info)
    Swag.require(queried == 0)
    Swag.require(guarded.before == 0x123456789ABCDEF0 and guarded.after == 0xFEDCBA9876543210)
    Swag.require(guarded.info.stx_size == cast(u64, LargeSize))
    Swag.require((guarded.info.stx_mode & S_IFMT) == S_IFREG)
    Swag.require((guarded.info.stx_mask & STATX_BASIC_STATS) == STATX_BASIC_STATS)
    var ordinary: stat
    let compared = fstat(descriptor, &ordinary)
    Swag.require(compared == 0 and ordinary.st_ino == guarded.info.stx_ino)
    Swag.require(ordinary.st_atim.tv_sec == guarded.info.stx_atime.tv_sec and ordinary.st_atim.tv_nsec == guarded.info.stx_atime.tv_nsec)
    if guarded.info.stx_mask & STATX_BTIME do
        Swag.require(guarded.info.stx_btime.tv_nsec < 1_000_000_000)
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
    Swag.require(created == 0)
    probe.mutex.lock()
    while probe.id == 0 do
        probe.changed.wait(&probe.mutex)
    probe.mutex.unlock()
    Swag.require(probe.id > 0 and probe.id != gettid())
    let pending = pthread_tryjoin_np(thread, null)
    Swag.require(pending == EBUSY)
    var policy:    s32
    var parameter: sched_param
    let queried = pthread_getschedparam(thread, &policy, &parameter)
    Swag.require(queried == 0)
    let invalid = pthread_setschedparam(thread, -1, &parameter)
    Swag.require(invalid == EINVAL)
    parameter.sched_priority = 0
    let normalized = pthread_setschedparam(thread, SCHED_OTHER, &parameter)
    Swag.require(normalized == 0)
    probe.mutex.lock()
    probe.released = true
    probe.changed.wake()
    probe.mutex.unlock()
    var result: *void?
    let joined = pthread_join(thread, &result)
    Swag.require(joined == 0 and result == &probe and probe.value == 73)
}

#[Swag.TestTag("integration.native")]
#test
{
    var first: *ifaddrs?
    let queried = getifaddrs(&first)
    Swag.require(queried == 0)
    if first
    {
        defer freeifaddrs(unwrap first)
        var current = first
        while current
        {
            let adapter = current
            current = adapter.ifa_next
            let name = unwrap adapter.ifa_name
            Swag.require(name[0] != 0)
            if adapter.ifa_addr
            {
                let address = adapter.ifa_addr
                if address.sa_family == AF_PACKET
                {
                    let packet = cast(const *sockaddr_ll, cast(const *void, address))
                    let index  = if_nametoindex(name)
                    Swag.require(index != 0 and index == cast(u32, packet.sll_ifindex))
                }
            }
        }
    }

    var guarded: { before: u64, mask: [1024] u8, after: u64 }
    guarded.before = 0x123456789ABCDEF0
    guarded.after  = 0xFEDCBA9876543210
    let affinity = sched_getaffinity(0, #sizeof(guarded.mask), &guarded.mask[0])
    Swag.require(affinity == 0)
    Swag.require(guarded.before == 0x123456789ABCDEF0 and guarded.after == 0xFEDCBA9876543210)
    var hasProcessor = false
    for byte in guarded.mask where byte != 0 do
        hasProcessor = true
    Swag.require(hasProcessor)
}

#[Swag.TestTag("integration.native")]
#test
{
    const Template = "/tmp/swag-linux-open-XXXXXX"
    var temporary: [128] u8
    for byte, index in Template do
        temporary[index] = byte
    let created = mkdtemp(temporary.buffer)
    Swag.require(created == temporary.buffer)
    defer discard unlinkat(AT_FDCWD, temporary.buffer, AT_REMOVEDIR)
    let directory = openat(AT_FDCWD, temporary.buffer, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    Swag.require(directory >= 0)
    defer discard close(directory)
    let original = openat(directory, "data".buffer, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOCTTY, 0x180'u32)
    Swag.require(original >= 0)
    defer discard close(original)
    defer discard unlinkat(directory, "data".buffer, 0)
    let written = write(original, "abc".buffer, 3)
    Swag.require(written == 3)
    let flags = fcntl(original, F_GETFD)
    Swag.require(flags >= 0 and (flags & FD_CLOEXEC) != 0)
    let duplicate      = openat(directory, "data".buffer, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0x180'u32)
    let duplicateError = errno()
    Swag.require(duplicate == -1 and duplicateError == EEXIST)
    var before: stat
    let preserved = fstat(original, &before)
    Swag.require(preserved == 0 and before.st_size == 3 and (before.st_mode & 0x7F) == 0)
    let inherited = openat(directory, "data".buffer, O_RDONLY | O_NOCTTY)
    Swag.require(inherited >= 0)
    defer discard close(inherited)
    let inheritedFlags = fcntl(inherited, F_GETFD)
    Swag.require(inheritedFlags >= 0 and (inheritedFlags & FD_CLOEXEC) == 0)
    let truncated = openat(directory, "data".buffer, O_WRONLY | O_TRUNC | O_CLOEXEC)
    Swag.require(truncated >= 0)
    defer discard close(truncated)
    var after: stat
    let observed = fstat(original, &after)
    Swag.require(observed == 0 and after.st_size == 0 and after.st_ino == before.st_ino)
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
    Swag.require(queried == 0)
    Swag.require(guarded.before == 0x123456789ABCDEF0 and guarded.after == 0xFEDCBA9876543210)
    if found
    {
        Swag.require(found == &guarded.entry and guarded.entry.pw_uid == uid)
        let homeAddress   = cast(u64, guarded.entry.pw_dir)
        let bufferAddress = cast(u64, buffer.buffer)
        Swag.require(homeAddress >= bufferAddress and homeAddress < bufferAddress + buffer.count)
        var small: [1] u8
        found = null
        let shortBuffer = getpwuid_r(uid, &guarded.entry, small.buffer, small.count, &found)
        Swag.require(shortBuffer == ERANGE and found == null)
        Swag.require(guarded.before == 0x123456789ABCDEF0 and guarded.after == 0xFEDCBA9876543210)
    }
}

#[Swag.TestTag("integration.native")]
#test
{
    const Template = "/tmp/swag-linux-realpath-XXXXXX"
    var temporary: [128] u8
    for byte, index in Template do
        temporary[index] = byte
    let created = mkdtemp(temporary.buffer)
    Swag.require(created == temporary.buffer)
    defer discard unlinkat(AT_FDCWD, temporary.buffer, AT_REMOVEDIR)
    let directory = openat(AT_FDCWD, temporary.buffer, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    Swag.require(directory >= 0)
    defer discard close(directory)
    let target = mkdirat(directory, "target".buffer, 0x1C0)
    Swag.require(target == 0)
    defer discard unlinkat(directory, "target".buffer, AT_REMOVEDIR)
    let deep = mkdirat(directory, "target/deep".buffer, 0x1C0)
    Swag.require(deep == 0)
    defer discard unlinkat(directory, "target/deep".buffer, AT_REMOVEDIR)
    let linked = symlinkat("target/deep".buffer, directory, "link".buffer)
    Swag.require(linked == 0)
    defer discard unlinkat(directory, "link".buffer, 0)
    let root = unwrap realpath(temporary.buffer, null)
    defer free(root)
    let rootView = cast(string, cast(cstring, root))
    var input, expected: [4096] u8
    for byte, index in rootView
    {
        input[index]    = byte
        expected[index] = byte
    }

    for byte, index in "/link/.." do
        input[rootView.count + index] = byte
    for byte, index in "/target" do
        expected[rootView.count + index] = byte
    let resolved = unwrap realpath(input.buffer, null)
    defer free(resolved)
    Swag.require(cast(string, cast(cstring, resolved)) == cast(string, cast(cstring, expected.buffer)))
    let looped = symlinkat("loop".buffer, directory, "loop".buffer)
    Swag.require(looped == 0)
    defer discard unlinkat(directory, "loop".buffer, 0)
    for byte, index in "/loop" do
        input[rootView.count + index] = byte
    input[rootView.count + 5] = 0
    let loopResult = realpath(input.buffer, null)
    let loopError  = errno()
    Swag.require(loopResult == null and loopError == ELOOP)
}

#[Swag.TestTag("integration.native")]
#test
{
    const Template = "/tmp/swag-linux-inotify-XXXXXX"
    var temporary: [128] u8
    for byte, index in Template do
        temporary[index] = byte
    let created = mkdtemp(temporary.buffer)
    Swag.require(created == temporary.buffer)
    defer discard unlinkat(AT_FDCWD, temporary.buffer, AT_REMOVEDIR)
    let directory = openat(AT_FDCWD, temporary.buffer, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    Swag.require(directory >= 0)
    defer discard close(directory)
    let notification = inotify_init1(IN_CLOEXEC | IN_NONBLOCK)
    Swag.require(notification >= 0)
    defer discard close(notification)
    let flags = fcntl(notification, F_GETFD)
    Swag.require(flags >= 0 and (flags & FD_CLOEXEC) != 0)
    let wd = inotify_add_watch(notification, temporary.buffer, IN_CREATE | IN_MOVED_FROM | IN_MOVED_TO | IN_ONLYDIR)
    Swag.require(wd >= 0)
    var fds: [2] pollfd
    var cancellation: [2] s32
    let piped = pipe2(cancellation.buffer, O_CLOEXEC | O_NONBLOCK)
    Swag.require(piped == 0)
    defer discard close(cancellation[0])
    defer discard close(cancellation[1])
    fds[0] = {fd: notification, events: POLLIN}
    fds[1] = {fd: cancellation[0], events: POLLIN}
    let idle = poll(fds.buffer, fds.count, 0)
    Swag.require(idle == 0)
    let file = openat(directory, "before".buffer, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0x180'u32)
    Swag.require(file >= 0)
    discard close(file)
    defer discard unlinkat(directory, "before".buffer, 0)
    defer discard unlinkat(directory, "after".buffer, 0)
    let ready = poll(fds.buffer, fds.count, 1000)
    Swag.require(ready == 1 and (fds[0].revents & POLLIN) != 0 and fds[1].revents == 0)
    var guarded: { before: u64, bytes: [32] u8, after: u64 }
    guarded.before = 0x123456789ABCDEF0
    guarded.after  = 0xFEDCBA9876543210
    let added = read(notification, guarded.bytes.buffer, guarded.bytes.count)
    Swag.require(added == 32)
    let event = cast(const *inotify_event, cast(const *void, guarded.bytes.buffer))
    Swag.require(event.wd == wd and event.mask == IN_CREATE and event.len == 16)
    Swag.require(cast(string, cast(cstring, guarded.bytes.buffer + 16)) == "before")
    let moved = renameat(directory, "before".buffer, directory, "after".buffer)
    Swag.require(moved == 0)
    let oldRead = read(notification, guarded.bytes.buffer, guarded.bytes.count)
    Swag.require(oldRead == 32 and event.mask == IN_MOVED_FROM and event.cookie != 0)
    let cookie = event.cookie
    Swag.require(cast(string, cast(cstring, guarded.bytes.buffer + 16)) == "before")
    let newRead = read(notification, guarded.bytes.buffer, guarded.bytes.count)
    Swag.require(newRead == 32 and event.mask == IN_MOVED_TO and event.cookie == cookie)
    Swag.require(cast(string, cast(cstring, guarded.bytes.buffer + 16)) == "after")
    let emptyRead  = read(notification, guarded.bytes.buffer, guarded.bytes.count)
    let emptyError = errno()
    Swag.require(emptyRead == -1 and emptyError == EAGAIN)
    Swag.require(guarded.before == 0x123456789ABCDEF0 and guarded.after == 0xFEDCBA9876543210)
    let signalled = write(cancellation[1], "x".buffer, 1)
    Swag.require(signalled == 1)
    let awakened = poll(fds.buffer, fds.count, 1000)
    Swag.require(awakened == 1 and fds[0].revents == 0 and (fds[1].revents & POLLIN) != 0)
    let removed = inotify_rm_watch(notification, wd)
    Swag.require(removed == 0)
    let ignored = read(notification, guarded.bytes.buffer, guarded.bytes.count)
    Swag.require(ignored == 16 and event.mask == IN_IGNORED and event.wd == wd and event.len == 0)
}

#[Swag.TestTag("integration.native")]
#test
{
    var guardedActions:    { before: u64, value: posix_spawn_file_actions_t, after: u64 }
    var guardedAttributes: { before: u64, value: posix_spawnattr_t, after: u64 }
    guardedActions.before    = 0x123456789ABCDEF0
    guardedActions.after     = 0xFEDCBA9876543210
    guardedAttributes.before = guardedActions.before
    guardedAttributes.after  = guardedActions.after
    let actionsInitialized = posix_spawn_file_actions_init(&guardedActions.value)
    Swag.require(actionsInitialized == 0)
    defer discard posix_spawn_file_actions_destroy(&guardedActions.value)
    let attributesInitialized = posix_spawnattr_init(&guardedAttributes.value)
    Swag.require(attributesInitialized == 0)
    defer discard posix_spawnattr_destroy(&guardedAttributes.value)
    var mask, defaults: sigset_t
    let emptyMask     = sigemptyset(&mask)
    let emptyDefaults = sigemptyset(&defaults)
    let defaultPipe   = sigaddset(&defaults, SIGPIPE)
    Swag.require(emptyMask == 0 and emptyDefaults == 0 and defaultPipe == 0)
    let masked  = posix_spawnattr_setsigmask(&guardedAttributes.value, &mask)
    let reset   = posix_spawnattr_setsigdefault(&guardedAttributes.value, &defaults)
    let flagged = posix_spawnattr_setflags(&guardedAttributes.value, POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF)
    Swag.require(masked == 0 and reset == 0 and flagged == 0)
    var descriptors: [2] s32
    let piped = pipe2(descriptors.buffer, O_CLOEXEC)
    Swag.require(piped == 0)
    defer discard close(descriptors[0])
    defer if descriptors[1] >= 0 do
        discard close(descriptors[1])
    let redirected       = posix_spawn_file_actions_adddup2(&guardedActions.value, descriptors[1], 1)
    let closedRead       = posix_spawn_file_actions_addclose(&guardedActions.value, descriptors[0])
    let closedWrite      = posix_spawn_file_actions_addclose(&guardedActions.value, descriptors[1])
    let changedDirectory = posix_spawn_file_actions_addchdir_np(&guardedActions.value, "/".buffer)
    let openedInput      = posix_spawn_file_actions_addopen(&guardedActions.value, 0, "/dev/null".buffer, O_RDONLY, 0)
    Swag.require(redirected == 0 and
                closedRead == 0 and
                closedWrite == 0 and
                changedDirectory == 0 and
                openedInput == 0)
    let arguments = ["sh", "-c", "printf '<%s>' \"$@\"; printf '<%s>' \"$SWAG_PROCESS_NATIVE\"; pwd; exit 37", "probe", "", "a b", "a\"b", "tail\\", "é"]
    var argv: [10] ([*] u8?)
    for argument, index in arguments do
        argv[index] = cast #unconst ([*] u8, argument.buffer)
    var envp: [2] ([*] u8?)
    envp[0] = cast #unconst ([*] u8, "SWAG_PROCESS_NATIVE=value".buffer)
    var child: s32
    let spawned = posix_spawn(&child, "/bin/sh".buffer, &guardedActions.value, &guardedAttributes.value, argv.buffer, envp.buffer)
    Swag.require(spawned == 0 and child > 0)
    defer if child > 0
    {
        discard kill(child, SIGKILL)
        while waitpid(child, null, 0) < 0 and errno() == EINTR {}
    }

    let closed = close(descriptors[1])
    descriptors[1] = -1
    Swag.require(closed == 0)
    var buffer: [128] u8
    var count = 0'u64
    for
    {
        let received = read(descriptors[0], buffer.buffer + count, buffer.count - count)
        if received == 0 do
            break
        if received < 0 and errno() == EINTR do
            continue
        Swag.require(received > 0)
        count += cast(u64, received)
        Swag.require(count < buffer.count)
    }

    var status: s32
    var waited: s32
    for
    {
        waited = waitpid(child, &status, 0)
        if waited >= 0 or errno() != EINTR do
            break
    }

    let expectedChild = child
    if waited == child do
        child = 0
    Swag.require(waited == expectedChild and WIFEXITED(status) and WEXITSTATUS(status) == 37)
    Swag.require(not WIFSIGNALED(status))
    Swag.require(cast(string, buffer[until count]) == "<><a b><a\"b><tail\\><é><value>/\n")
    Swag.require(guardedActions.before == 0x123456789ABCDEF0 and guardedActions.after == 0xFEDCBA9876543210)
    Swag.require(guardedAttributes.before == 0x123456789ABCDEF0 and guardedAttributes.after == 0xFEDCBA9876543210)
    let missing = posix_spawnp(null, "/swag-process-does-not-exist".buffer, null, null, argv.buffer, envp.buffer)
    Swag.require(missing == ENOENT)
}

#[Swag.TestTag("integration.native")]
#test
{
    var argv: [3] ([*] u8?)
    argv[0] = cast #unconst ([*] u8, "sleep".buffer)
    argv[1] = cast #unconst ([*] u8, "30".buffer)
    var envp:  [1] ([*] u8?)
    var child: s32
    let spawned = posix_spawnp(&child, "/bin/sleep".buffer, null, null, argv.buffer, envp.buffer)
    Swag.require(spawned == 0 and child > 0)
    defer if child > 0
    {
        discard kill(child, SIGKILL)
        while waitpid(child, null, 0) < 0 and errno() == EINTR {}
    }

    var status: s32
    let pending = waitpid(child, &status, WNOHANG)
    Swag.require(pending == 0)
    let killed = kill(child, SIGKILL)
    Swag.require(killed == 0)
    var waited: s32
    for
    {
        waited = waitpid(child, &status, 0)
        if waited >= 0 or errno() != EINTR do
            break
    }

    let expectedChild = child
    if waited == child do
        child = 0
    Swag.require(waited == expectedChild and WIFSIGNALED(status) and WTERMSIG(status) == SIGKILL)
    Swag.require(not WIFEXITED(status))
    let reapedAgain = waitpid(expectedChild, &status, WNOHANG)
    let reapError   = errno()
    Swag.require(reapedAgain == -1 and reapError == ECHILD)
}

#[Swag.TestTag("integration.native")]
#test
{
    var guarded: { before: u64, bytes: [4097] u8, after: u64 }
    guarded.before = 0x123456789ABCDEF0
    guarded.after  = 0xFEDCBA9876543210
    let tiny = readlinkat(AT_FDCWD, "/proc/self/exe".buffer, guarded.bytes.buffer, 1)
    Swag.require(tiny == 1 and guarded.bytes[0] == '/' and guarded.bytes[1] == 0)
    let length = readlinkat(AT_FDCWD, "/proc/self/exe".buffer, guarded.bytes.buffer, 4096)
    Swag.require(length > 0 and length < 4096 and guarded.bytes[cast(u64, length)] == 0)
    let original = openat(AT_FDCWD, "/proc/self/exe".buffer, O_RDONLY | O_CLOEXEC)
    Swag.require(original >= 0)
    defer discard close(original)
    let resolved = openat(AT_FDCWD, guarded.bytes.buffer, O_RDONLY | O_CLOEXEC)
    Swag.require(resolved >= 0)
    defer discard close(resolved)
    var originalInfo, resolvedInfo: stat
    let originalRead = fstat(original, &originalInfo)
    let resolvedRead = fstat(resolved, &resolvedInfo)
    Swag.require(originalRead == 0 and resolvedRead == 0)
    Swag.require(originalInfo.st_dev == resolvedInfo.st_dev and originalInfo.st_ino == resolvedInfo.st_ino)
    Swag.require(guarded.before == 0x123456789ABCDEF0 and guarded.after == 0xFEDCBA9876543210)
    let missing      = readlinkat(AT_FDCWD, "/proc/self/swag-missing-exe".buffer, guarded.bytes.buffer, guarded.bytes.count)
    let missingError = errno()
    Swag.require(missing == -1 and missingError == ENOENT)
    let image = dlopen(null, RTLD_NOW | RTLD_LOCAL)
    Swag.require(image != null)
    defer discard dlclose(unwrap image)
    let address = dlsym(image, "environ".buffer)
    Swag.require(address != null)
    let tableAddress = cast(const *([*] ([*] u8?)?), address)
    let table        = tableAddress[]
    let directPath   = getenv("PATH".buffer)
    var foundPath    = false
    if table
    {
        var index = 0'u64
        for
        {
            let entry = table[index]
            if not entry do
                break
            let text = cast(string, cast(cstring, entry))
            if text.count >= 5 and text[until 5] == "PATH="
            {
                Swag.require(directPath != null)
                Swag.require(text[5 to ] == cast(string, cast(cstring, directPath)))
                foundPath = true
            }

            index += 1
        }
    }

    Swag.require(foundPath == (directPath != null))
}

#[Swag.TestTag("integration.native")]
#test
{
    var blocked, previous, pending: sigset_t
    let emptied = sigemptyset(&blocked)
    let added   = sigaddset(&blocked, SIGPIPE)
    Swag.require(emptied == 0 and added == 0)
    let masked = pthread_sigmask(SIG_BLOCK, &blocked, &previous)
    Swag.require(masked == 0)
    defer discard pthread_sigmask(SIG_SETMASK, &previous, null)
    let queried        = sigpending(&pending)
    let alreadyPending = sigismember(&pending, SIGPIPE)
    Swag.require(queried == 0 and alreadyPending >= 0)
    var immediate: timespec
    defer if alreadyPending == 0 do
        discard sigtimedwait(&blocked, null, &immediate)
    var descriptors: [2] s32
    let piped = pipe2(descriptors.buffer, O_CLOEXEC | O_NONBLOCK)
    Swag.require(piped == 0)
    defer discard close(descriptors[1])
    let flags      = fcntl(descriptors[0], F_GETFL)
    let reset      = fcntl(descriptors[0], F_SETFL, flags & ~O_NONBLOCK)
    let readFlags  = fcntl(descriptors[0], F_GETFL)
    let writeFlags = fcntl(descriptors[1], F_GETFL)
    Swag.require(flags >= 0 and reset == 0 and (readFlags & O_NONBLOCK) == 0 and (writeFlags & O_NONBLOCK) != 0)
    let sent     = write(descriptors[1], "bytes".buffer, 5)
    var available: s32
    let measured = ioctl(descriptors[0], FIONREAD, &available)
    Swag.require(sent == 5 and measured == 0 and available == 5)
    let closedRead = close(descriptors[0])
    Swag.require(closedRead == 0)
    let written    = write(descriptors[1], "x".buffer, 1)
    let writeError = errno()
    Swag.require(written == -1 and writeError == EPIPE)
    let pendingAfter = sigpending(&pending)
    let pipePending  = sigismember(&pending, SIGPIPE)
    Swag.require(pendingAfter == 0 and pipePending == 1)
    if alreadyPending == 0
    {
        let consumed = sigtimedwait(&blocked, null, &immediate)
        Swag.require(consumed == SIGPIPE)
        let noMore      = sigtimedwait(&blocked, null, &immediate)
        let noMoreError = errno()
        Swag.require(noMore == -1 and noMoreError == EAGAIN)
    }

    let memory = calloc(4, #sizeof(u64))
    Swag.require(memory != null)
    defer free(memory)
    let words = cast([*] u64, memory)
    for index in 4 do
        Swag.require(words[index] == 0)
}

#[Swag.TestTag("integration.native")]
#test
{
    // Layout and ioctl values cross-checked with linux/input.h on GNU/Linux x86-64.
    Swag.require(#sizeof(input_absinfo) == 24 and #sizeof(input_event) == 24)
    Swag.require(#sizeof(ff_effect) == 48 and #offsetof(ff_effect.u) == 16)
    Swag.require(#offsetof(ff_effect.trigger) == 6 and #offsetof(ff_effect.replay) == 10)
    Swag.require(EVIOCGKEY(96) == 0x80604518 and EVIOCGABS(ABS_X) == 0x80184540)
    Swag.require(EVIOCSFF == 0x40304580 and EVIOCRMFF == 0x40044581)
    var guarded: struct { before: u64; effect: ff_effect; after: u64 }
    guarded.before      = 0x123456789ABCDEF0
    guarded.after       = 0xFEDCBA9876543210
    guarded.effect.type = FF_RUMBLE
    guarded.effect.id   = -1
    let rumble = cast(*ff_rumble_effect, cast(*void, &guarded.effect.u))
    rumble.strong_magnitude = 0x1234
    rumble.weak_magnitude   = 0x5678
    Swag.require(guarded.effect.u[0] == 0x56781234)
    let fd = openat(AT_FDCWD, "/dev/null".buffer, O_RDWR | O_CLOEXEC)
    Swag.require(fd >= 0)
    defer discard close(fd)
    let uploaded    = ioctl(fd, EVIOCSFF, &guarded.effect)
    let uploadError = errno()
    Swag.require(uploaded == -1 and uploadError == ENOTTY and guarded.effect.id == -1)
    var axes: input_absinfo
    let queried    = ioctl(fd, EVIOCGABS(ABS_X), &axes)
    let queryError = errno()
    Swag.require(queried == -1 and queryError == ENOTTY)
    Swag.require(guarded.before == 0x123456789ABCDEF0 and guarded.after == 0xFEDCBA9876543210)
}
