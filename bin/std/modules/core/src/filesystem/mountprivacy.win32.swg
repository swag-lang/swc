#global if WINDOWS
#global public
#global namespace File

using Win32

internal func mountPrivacyPathNative(path: string)->String
{
    var candidate = catch Path.absolute(path) { return {} }
    for
    {
        let name   = Utf16.toZeroTerminated(candidate)
        let handle = catch CreateFileW(name.buffer, FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, null, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, null)
        {
            let parent = Path.directoryName(candidate)
            if not parent or Path.equals(parent, candidate) do
                return {}
            candidate = String.from(parent)
            continue
        }

        defer CloseHandle(handle)
        var buffer: Array'u16
        buffer.resize(32768)
        let length = GetFinalPathNameByHandleW(handle, buffer.storage(), cast(u32, buffer.count), 0)
        if not length or length >= buffer.count do
            return {}
        return Utf8.fromUtf16(buffer.toSlice()[until length])
    }
}

internal func mountPrivacyProtectedRootNative(path: string)->String
{
    const Prefix = #raw "\\?\UNC\swagvault\"
    if path.count <= Prefix.count or not Path.equals(path[until Prefix.count], Prefix) do
        return {}
    var end = Prefix.count
    while end < path.count and not Path.isDirectorySeparator(path[end]) do
        end += 1
    return String.from(path[until end])
}

internal impl MountPrivacyPublisher
{
    mtd openNative() fail
    {
        let name   = Utf16.toZeroTerminated(Format.toString("Local\\%", .channel))
        let handle = try CreateFileMappingW(INVALID_HANDLE_VALUE, null, PAGE_READWRITE, 0, #sizeof(MountPrivacyData), name.buffer)
        defer if not .handle do
            CloseHandle(handle)
        let view = try MapViewOfFile(handle, FILE_MAP_WRITE, 0, 0, #sizeof(MountPrivacyData))
        defer if not .data do
            discard catch UnmapViewOfFile(view)
        let data  = assume cast(*MountPrivacyData, view)
        let flags = Atomic.get(&data.flags)
        if flags & 2 or Atomic.compareExchange(&data.flags, flags, 3) != flags do
            fail Errors.BadParameterError{}
        Atomic.exchange(&data.sequence, 0)
        .handle = handle
        .data   = data
    }

    mtd closeNative()
    {
        discard catch UnmapViewOfFile(.data)
        CloseHandle(.handle)
        .handle = null
        .data   = null
    }
}

internal func readMountPrivacyNative(channel: string, result: *MountPrivacy)->bool
{
    let name     = Utf16.toZeroTerminated(Format.toString("Local\\%", channel))
    let handle   = catch OpenFileMappingW(FILE_MAP_READ, FALSE, name.buffer) { return false }
    var attached = false
    defer if not attached do
        CloseHandle(handle)
    let view = catch MapViewOfFile(handle, FILE_MAP_READ, 0, 0, #sizeof(MountPrivacyData)) { return false }
    defer if not attached do
        discard catch UnmapViewOfFile(view)
    let data = assume cast(*MountPrivacyData, view)
    if (Atomic.get(&data.flags) & 2) == 0 or not readMountPrivacyData(data, result) do
        return false
    let reader = Memory.new'MountPrivacyReader()
    reader.handle = handle
    reader.data   = data
    result.reader = reader
    attached      = true
    return true
}

internal func closeMountPrivacyReaderNative(reader: *MountPrivacyReader)
{
    discard catch UnmapViewOfFile(reader.data)
    CloseHandle(reader.handle)
}
