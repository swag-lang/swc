#global if WINDOWS
#global public
#global namespace File

using Win32

impl MappedRegion
{
    internal mtd mapNative(sourceHandle: FileHandle, offset, length: u64, access: MapAccess) fail
    {
        var protect:       DWORD
        var desiredAccess: DWORD
        switch access
        {
        case .Read:
            protect       = PAGE_READONLY
            desiredAccess = FILE_MAP_READ

        case .ReadWrite:
            protect       = PAGE_READWRITE
            desiredAccess = FILE_MAP_WRITE

        case .CopyOnWrite:
            protect       = PAGE_WRITECOPY
            desiredAccess = FILE_MAP_COPY
        }

        var systemInfo: SYSTEM_INFO
        GetSystemInfo(&systemInfo)
        let granularity   = cast(u64) systemInfo.dwAllocationGranularity
        let alignedOffset = offset / granularity * granularity
        let prefix        = offset - alignedOffset
        if length > Swag.U64.Max - prefix do
            fail Errors.OverflowError{}
        let mappedLength = length + prefix

        let mapping = CreateFileMappingW(cast(HANDLE) sourceHandle, null, protect, 0, 0, null)
        defer if !.mapHandle do
            CloseHandle(mapping)

        let currentProcess = GetCurrentProcess()
        var duplicate: HANDLE
        DuplicateHandle(currentProcess, cast(HANDLE) sourceHandle, currentProcess, &duplicate, 0, FALSE, DUPLICATE_SAME_ACCESS)
        defer if !.fileHandle do
            CloseHandle(duplicate)

        let nativeView = MapViewOfFile(mapping, desiredAccess, cast(DWORD) (alignedOffset >> 32), cast(DWORD) alignedOffset, mappedLength)
        defer if !.nativeView do
            discard catch UnmapViewOfFile(nativeView)

        .mapHandle  = cast(FileHandle) mapping
        .fileHandle = cast(FileHandle) duplicate
        .nativeView = nativeView
        .view       = cast([*] u8) nativeView! + prefix
    }

    internal mtd closeNative()
    {
        if .nativeView
        {
            discard catch UnmapViewOfFile(.nativeView)
            .nativeView = null
            .view       = null
        }

        if .mapHandle
        {
            CloseHandle(cast(HANDLE) .mapHandle)
            .mapHandle = null
        }

        if .fileHandle
        {
            CloseHandle(cast(HANDLE) .fileHandle)
            .fileHandle = null
        }

        .length = 0
        .offset = 0
        .valid  = false
    }

    internal mtd flushNative() fail
    {
        FlushViewOfFile(.view, .length)
        catch FlushFileBuffers(cast(HANDLE) .fileHandle) as err
        Errors.transformWinErrors(err)
    }
}
