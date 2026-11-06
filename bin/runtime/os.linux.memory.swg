#global if #os == Swag.TargetOs.Linux

namespace __LinuxRT
{
    struct DirectoryEntry
    {
        inode:        u64
        offset:       s64
        recordLength: u16
        kind:         u8
        name:         [256] u8
    }

    const OpenDirectory       = 0x10000's32
    const CloseOnExec         = 0x80000's32
    const LockExclusive       = 2's32
    const MapPrivateAnonymous = 0x22's32
    const MapShared           = 1's32
    const ProtectReadWrite    = 3's32
    const DiscardPages        = 4's32

    #[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
    {
        func getpid()->s32
        func open(path: const [*] u8, flags: s32)->s32
        func openat(directory: s32, path: const [*] u8, flags: s32)->s32
        func close(descriptor: s32)->s32
        func flock(descriptor: s32, operation: s32)->s32
        func opendir(path: const [*] u8)->*void?
        func closedir(directory: *void)->s32
        func dirfd(directory: *void)->s32
        func readdir(directory: *void)->*DirectoryEntry?
        func readlinkat(directory: s32, path: const [*] u8, buffer: [*] u8, capacity: u64)->s64
        func memfd_create(name: const [*] u8, flags: u32)->s32
        func ftruncate(descriptor: s32, length: s64)->s32
        func lseek(descriptor: s32, offset: s64, origin: s32)->s64
        func mmap(address: *void?, length: u64, protection: s32, flags: s32, descriptor: s32, offset: s64)->*void?
        func mprotect(address: *void?, length: u64, protection: s32)->s32
        func madvise(address: *void?, length: u64, advice: s32)->s32
        func munmap(address: *void?, length: u64)->s32
    }
}

// Anonymous memfds provide one process-lifetime anchor without a persistent /dev/shm name.
// All artifacts discover the retained descriptor through procfs. Independent opens of the
// process directory share its inode lock, serializing first publication across threads and
// independently loaded runtimes. CLOEXEC prevents the anchor crossing an exec boundary.
#[Swag.Safety(.ValueBorrow, false)]
func __hostProcessStorage(key: u32, size: u32)->*void?
{
    using __LinuxRT
    if size == 0 do
        return null

    let lock = open("/proc/self".buffer, OpenDirectory | CloseOnExec)
    if lock < 0 do
        return null
    defer discard close(lock)
    while flock(lock, LockExclusive) != 0
    {
        if __errno_location()[] != Interrupted do
            return null
    }

    const Prefix = "Swag.Rt."
    const Digits = "0123456789abcdef"
    var name: [26] u8
    Swag.memcpy(&name[0], Prefix.buffer, Prefix.count)
    let processId = cast(u32, getpid())
    for index in 8'u32
    {
        name[8 + index]  = Digits[(processId >> (28 - index * 4)) & 15]
        name[17 + index] = Digits[(key >> (28 - index * 4)) & 15]
    }

    name[16] = 46     // '.'; a forked process must not join its parent's registry.

    const LinkPrefix = "/memfd:"
    const LinkSuffix = " (deleted)"
    var wanted: [48] u8
    Swag.memcpy(&wanted[0], LinkPrefix.buffer, LinkPrefix.count)
    Swag.memcpy(&wanted[LinkPrefix.count], &name[0], 25)
    Swag.memcpy(&wanted[LinkPrefix.count + 25], LinkSuffix.buffer, LinkSuffix.count)
    const WantedLength = LinkPrefix.count + 25 + LinkSuffix.count

    let directory = opendir("/proc/self/fd".buffer)
    if not directory do
        return null
    defer discard closedir(unwrap directory)
    let directoryId = dirfd(directory)
    for
    {
        let entry = readdir(directory)
        if not entry do
            break
        var target: [64] u8
        let length = readlinkat(directoryId, &entry.name[0], &target[0], target.count)
        if length != cast(s64, WantedLength) or Swag.memcmp(&target[0], &wanted[0], WantedLength) != 0 do
            continue

        let descriptor = openat(directoryId, &entry.name[0], 2 | CloseOnExec)
        if descriptor < 0 do
            return null
        defer discard close(descriptor)
        if lseek(descriptor, 0, 2) != cast(s64, size) do
            return null
        let view = mmap(null, size, ProtectReadWrite, MapShared, descriptor, 0)
        return cast(s64, view) == -1 ? null : view
    }

    let descriptor = memfd_create(&name[0], 1)
    if descriptor < 0 do
        return null
    if ftruncate(descriptor, cast(s64, size)) != 0
    {
        discard close(descriptor)
        return null
    }

    let view = mmap(null, size, ProtectReadWrite, MapShared, descriptor, 0)
    if cast(s64, view) == -1
    {
        discard close(descriptor)
        return null
    }

    // Keep the descriptor discoverable until process exit; the kernel owns crash cleanup.
    return view
}

#[Swag.Safety(.ValueBorrow, false)]
func __hostProcessSingleton(key: u32, candidate: *void)->*void
{
    let view = __hostProcessStorage(key, 8)
    if not view do
        return candidate
    let previous = Swag.atomicCompareExchange(cast(*u64, view), 0, cast(u64, candidate))
    return previous == 0 ? candidate : cast(*void, previous)
}

private struct LinuxPageReservation
{
    next: *LinuxPageReservation?
    size: u64
    firstPageCommitted: bool
}

private struct LinuxPageRegistry
{
    lock:      *void?
    first:     *LinuxPageReservation?
    processId: s32
}

private const LinuxPageRegistryKey = 4'u32
private var linuxPageRegistryCache: u64

#[Swag.Safety(.ValueBorrow, false)]
private func __linuxPageRegistry()->*LinuxPageRegistry?
{
    let processId = __LinuxRT.getpid()
    let known = Swag.atomicLoad(&linuxPageRegistryCache)
    if known and cast(*LinuxPageRegistry, known).processId == processId do
        return cast(*LinuxPageRegistry, known)
    let registry = __hostProcessStorage(LinuxPageRegistryKey, #sizeof(LinuxPageRegistry))
    if not registry do
        return null
    cast(*LinuxPageRegistry, registry).processId = processId
    let previous = Swag.atomicCompareExchange(&linuxPageRegistryCache, known, cast(u64, registry))
    if previous != known
    {
        discard __LinuxRT.munmap(registry, #sizeof(LinuxPageRegistry))
        return cast(*LinuxPageRegistry, previous)
    }

    // A forked child has its own process-storage anchor. The inherited mapping still belongs to
    // the parent's reservation list and must not receive the child's private mapping addresses.
    if known do
        discard __LinuxRT.munmap(cast(*void, known), #sizeof(LinuxPageRegistry))
    return cast(*LinuxPageRegistry, registry)
}

// One hidden metadata page precedes each reservation. The registry retains allocation identity
// when Linux splits or merges VMAs, so an electric allocation never probes an inaccessible page.
#[Swag.Safety(.ValueBorrow, false)]
func __hostPageReserve(size: u64)->[*] u8?
{
    using __LinuxRT
    if size == 0 or
       size % AllocatorHostCommitGranularity != 0 or
       size > Swag.U64.Max - AllocatorHostCommitGranularity do
        return null
    let registry = __linuxPageRegistry()
    if not registry do
        return null
    let total   = size + AllocatorHostCommitGranularity
    let mapping = mmap(null, total, 0, MapPrivateAnonymous, -1, 0)
    if cast(s64, mapping) == -1 do
        return null
    if mprotect(mapping, AllocatorHostCommitGranularity, ProtectReadWrite) != 0
    {
        discard munmap(mapping, total)
        return null
    }

    let record = cast(*LinuxPageReservation, unwrap mapping)
    record.size = size
    __hostLockExclusive(&registry.lock)
    record.next    = registry.first
    registry.first = record
    __hostUnlockExclusive(&registry.lock)
    return cast([*] u8, cast(u64, mapping) + AllocatorHostCommitGranularity)
}

#[Swag.Safety(.ValueBorrow, false)]
private func __linuxSetPageCommitted(address: *void?, size: u64, committed: bool)
{
    let registry = __linuxPageRegistry()
    if not registry do
        return
    __hostLockExclusive(&registry.lock)
    defer __hostUnlockExclusive(&(unwrap registry).lock)
    var record = registry.first
    while record
    {
        let base = cast(u64, record) + AllocatorHostCommitGranularity
        if cast(u64, address) == base and size >= AllocatorHostCommitGranularity
        {
            record.firstPageCommitted = committed
            return
        }

        record = record.next
    }
}

func __hostPageCommit(address: *void?, size: u64)->bool
{
    if __LinuxRT.mprotect(address, size, __LinuxRT.ProtectReadWrite) != 0 do
        return false
    __linuxSetPageCommitted(address, size, true)
    return true
}

func __hostPageDecommit(address: *void?, size: u64)
{
    #static if #safety(Swag.SafetyWhat.ValueBorrow)
    {
        if address
        {
            let location = #curlocation
            Swag.__valueBorrowWrite(address, size, &location)
        }
    }

    if __LinuxRT.mprotect(address, size, 0) == 0
    {
        __linuxSetPageCommitted(address, size, false)
        discard __LinuxRT.madvise(address, size, __LinuxRT.DiscardPages)
    }
}

func __hostPageRelease(address: *void?, size: u64)
{
    if not address do
        return
    #static if #safety(Swag.SafetyWhat.ValueBorrow)
    {
        let location = #curlocation
        Swag.__valueBorrowWrite(address, size, &location)
    }

    __linuxReleaseReservation(address, size)
}

func allocatorHostPageRelease(address: *void?, reservedSize, committedSize: u64)
{
    if not address do
        return
    #static if #safety(Swag.SafetyWhat.ValueBorrow)
    {
        let location = #curlocation
        Swag.__valueBorrowWrite(address, committedSize, &location)
    }

    __linuxReleaseReservation(address, reservedSize)
}

#[Swag.Safety(.ValueBorrow, false)]
private func __linuxReleaseReservation(address: *void, size: u64)
{
    let registry = __linuxPageRegistry()
    if not registry do
        return
    __hostLockExclusive(&registry.lock)
    defer __hostUnlockExclusive(&(unwrap registry).lock)
    var link = &registry.first
    while link[]
    {
        let record = unwrap link[]
        if cast(u64, record) + AllocatorHostCommitGranularity == cast(u64, address)
        {
            if record.size != size do
                return
            let next = record.next
            if __LinuxRT.munmap(record, size + AllocatorHostCommitGranularity) == 0 do
                link[] = next
            return
        }

        link = &record.next
    }
}

#[Swag.Safety(.ValueBorrow, false)]
func __hostPageAllocationBase(address: u64)->u64
{
    let registry = __linuxPageRegistry()
    if not registry do
        return 0
    __hostLockExclusive(&registry.lock)
    defer __hostUnlockExclusive(&(unwrap registry).lock)
    var record = registry.first
    while record
    {
        let base = cast(u64, record) + AllocatorHostCommitGranularity
        if address >= base and address - base < record.size do
            return record.firstPageCommitted ? base : 0
        record = record.next
    }

    return 0
}
