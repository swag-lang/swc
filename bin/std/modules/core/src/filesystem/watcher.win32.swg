#global if WINDOWS
#global public
#global namespace Directory

using Win32

private struct WatcherNative
{
    directory:     HANDLE
    event:         HANDLE
    overlapped:    OVERLAPPED
    buffer:        Array'u8
    pendingRename: String
    pending:       bool
    cancelled:     u32
}

private func watcherNative(value: *void?)->*WatcherNative => cast(*WatcherNative) value!

private func watchFilterNative(filter: WatchFilter)->DWORD
{
    var result: DWORD
    if filter.has(.FileName) do
        result |= FILE_NOTIFY_CHANGE_FILE_NAME
    if filter.has(.DirectoryName) do
        result |= FILE_NOTIFY_CHANGE_DIR_NAME
    if filter.has(.Attributes) do
        result |= FILE_NOTIFY_CHANGE_ATTRIBUTES
    if filter.has(.Size) do
        result |= FILE_NOTIFY_CHANGE_SIZE
    if filter.has(.LastWrite) do
        result |= FILE_NOTIFY_CHANGE_LAST_WRITE
    if filter.has(.LastAccess) do
        result |= FILE_NOTIFY_CHANGE_LAST_ACCESS
    if filter.has(.Creation) do
        result |= FILE_NOTIFY_CHANGE_CREATION
    if filter.has(.Security) do
        result |= FILE_NOTIFY_CHANGE_SECURITY
    return result
}

private func appendChange(changes: *Array'Change, kind: ChangeKind, root, relative: string, oldPath: string? = null)
{
    var change: Change
    change.kind = kind
    change.path = Path.combine(root, relative)
    if oldPath do
        change.oldPath = oldPath
    changes.add(#move change)
}

impl Watcher
{
    internal mtd openNative() fail
    {
        let raw   = Memory.alloc(#sizeof(WatcherNative))
        let state = cast(*WatcherNative) raw
        Swag.init(state, 1)
        defer if !.native
        {
            Swag.drop(state, 1)
            Memory.free(raw, #sizeof(WatcherNative))
        }

        let winPath = Utf16.toZeroTerminated(.root.toString())
        state.directory = CreateFileW(winPath.buffer, FILE_LIST_DIRECTORY, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, null, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED, null)
        defer if !.native and state.directory do
            CloseHandle(state.directory)

        state.event = CreateEventW(null, TRUE, FALSE, null)
        defer if !.native and state.event do
            CloseHandle(state.event)

        state.buffer.reserve(.options.bufferSize)
        state.buffer.count      = .options.bufferSize
        state.overlapped.hEvent = state.event
        .issueRead(state)
        .native = state
    }

    internal mtd closeNative()
    {
        if !.native do
            return

        let state = watcherNative(.native)
        .cancelNative()
        if state.pending
        {
            discard catch WaitForSingleObject(state.event, Swag.U32.Max)
            var transferred: DWORD
            discard catch GetOverlappedResult(state.directory, &state.overlapped, &transferred, FALSE)
            state.pending = false
        }

        CloseHandle(state.event)
        CloseHandle(state.directory)
        Swag.drop(state, 1)
        Memory.free(cast([*] void) state, #sizeof(WatcherNative))
        .native = null
    }

    internal mtd cancelNative()
    {
        let state = watcherNative(.native)
        if Atomic.exchange(&state.cancelled, 1) do
            return

        discard catch CancelIoEx(state.directory, &state.overlapped)
    }

    private mtd issueRead(state: *WatcherNative) fail
    {
        if state.pending do
            return

        state.overlapped.Internal     = 0
        state.overlapped.InternalHigh = 0
        state.overlapped.data.Pointer = null
        state.overlapped.hEvent       = state.event
        catch ResetEvent(state.event)
        discard ReadDirectoryChangesW(state.directory, state.buffer.buffer, cast(DWORD) state.buffer.count, .options.recurse ? TRUE : FALSE, watchFilterNative(.options.filter), null, &state.overlapped, null)
        state.pending = true

        // Cancellation can race the interval between the caller's state check and submission.
        // Rechecking after publication closes that gap without serializing the common path.
        if Atomic.get(&state.cancelled) do
            discard catch CancelIoEx(state.directory, &state.overlapped)
    }

    private mtd parseChanges(state: *WatcherNative, transferred: u32)->WatchBatch
    {
        var result: retval
        result.status = .Changes

        var offset = 0'u32
        for
        {
            let info     = cast(const *FILE_NOTIFY_INFORMATION) (state.buffer.buffer! + offset)
            let nameData = cast(const [*] u16) &info.FileName[0]
            var name     = Utf8.fromUtf16(Swag.makeSlice(nameData, cast(u64) info.FileNameLength / #sizeof(u16)))
            let relative = name.toString()

            if info.Action != FILE_ACTION_RENAMED_NEW_NAME and info.Action != FILE_ACTION_RENAMED_OLD_NAME and state.pendingRename.length
            {
                appendChange(&result.changes, .Removed, .root.toString(), state.pendingRename.toString())
                state.pendingRename.clear()
            }

            switch info.Action
            {
            case FILE_ACTION_ADDED:
                appendChange(&result.changes, .Added, .root.toString(), relative)

            case FILE_ACTION_REMOVED:
                appendChange(&result.changes, .Removed, .root.toString(), relative)

            case FILE_ACTION_MODIFIED:
                appendChange(&result.changes, .Modified, .root.toString(), relative)

            case FILE_ACTION_RENAMED_OLD_NAME:
                if state.pendingRename.length do
                    appendChange(&result.changes, .Removed, .root.toString(), state.pendingRename.toString())
                state.pendingRename = #move name

            case FILE_ACTION_RENAMED_NEW_NAME:
                if state.pendingRename.length
                {
                    let oldPath = Path.combine(.root.toString(), state.pendingRename.toString())
                    appendChange(&result.changes, .Renamed, .root.toString(), relative, oldPath.toString())
                    state.pendingRename.clear()
                }
                else
                {
                    appendChange(&result.changes, .Added, .root.toString(), relative)
                }

            default:
                appendChange(&result.changes, .Modified, .root.toString(), relative)
            }

            if !info.NextEntryOffset do
                break
            if info.NextEntryOffset > transferred - offset do
                break
            offset += info.NextEntryOffset
        }

        return result
    }

    internal mtd nextNative(waitMilliseconds: u32)->WatchBatch fail
    {
        let state = watcherNative(.native)
        if Atomic.get(&state.cancelled)
        {
            var cancelled: retval
            cancelled.status = .Cancelled
            return cancelled
        }

        .issueRead(state)
        if WaitForSingleObject(state.event, waitMilliseconds) == WAIT_TIMEOUT
        {
            var timedOut: retval
            timedOut.status = .TimedOut
            return timedOut
        }

        var transferred: DWORD
        catch GetOverlappedResult(state.directory, &state.overlapped, &transferred, FALSE) as err
        state.pending = false
        if err != null
        {
            let systemError = cast(const *Swag.SystemError) err
            if systemError.errorID == ERROR_OPERATION_ABORTED and Atomic.get(&state.cancelled)
            {
                var cancelled: retval
                cancelled.status = .Cancelled
                return cancelled
            }

            fail err
        }

        if !transferred
        {
            var overflow: retval
            overflow.status = .Overflow
            return overflow
        }

        return .parseChanges(state, transferred)
    }
}
