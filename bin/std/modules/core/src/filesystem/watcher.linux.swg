#global if #os == Swag.TargetOs.Linux
#global namespace Directory

private struct WatchedDirectory
{
    descriptor: s32
    path:       String
}

private struct PendingWatchMove
{
    cookie:    u32
    path:      String
    directory: bool
    report:    bool
    expires:   u64
}

private struct WatcherNative
{
    descriptor            = -1's32
    cancellation: [2] s32 = [-1, -1]
    allocator:    Swag.IAllocator?
    buffer:       Array'u8
    directories:  Array'WatchedDirectory
    moves:        Array'PendingWatchMove
    clock:        Time.Stopwatch
    cancelled:    Swag.AtomicValue'u32
    rootDescriptor        = -1's32
}

private func watcherNative(value: *void?)->*WatcherNative => cast(*WatcherNative, unwrap value)

private func watchPathContains(parent, path: string)->bool
{
    if parent == path do
        return true
    return Utf8.startsWith(path, parent) and
           path.count > parent.count and
           (parent[parent.count - 1] == '/' or path[parent.count] == '/')
}

private func appendWatchChange(changes: *Array'Change, kind: ChangeKind, path: string, oldPath: string = "")
{
    var change: Change
    change.kind    = kind
    change.path    = String.from(path)
    change.oldPath = String.from(oldPath)
    changes.add(#move change)
}

private func watchFilterNative(filter: WatchFilter)->u32
{
    var mask = Linux.IN_DELETE_SELF | Linux.IN_MOVE_SELF | Linux.IN_EXCL_UNLINK | Linux.IN_ONLYDIR

    // Name events also maintain recursive subscriptions and pair moves independently of filtering.
    mask |= Linux.IN_CREATE | Linux.IN_DELETE | Linux.IN_MOVED_FROM | Linux.IN_MOVED_TO
    if filter.has(.Size) or filter.has(.LastWrite) do
        mask |= Linux.IN_MODIFY
    if filter.has(.Attributes) or filter.has(.Security) do
        mask |= Linux.IN_ATTRIB
    if filter.has(.LastAccess) do
        mask |= Linux.IN_ACCESS
    return mask
}

private func dropWatcherNative(state: *WatcherNative)
{
    if state.descriptor >= 0 do
        discard Linux.close(state.descriptor)
    for descriptor in state.cancellation do
        if descriptor >= 0 do
            discard Linux.close(descriptor)
    let allocator = state.allocator
    Swag.drop(state, 1)
    Memory.free(state, #sizeof(WatcherNative), allocator)
}

internal impl Watcher
{
    mtd openNative() fail
    {
        if .options.filter == cast(WatchFilter, 0) or (.options.filter & ~WatchFilter.All) != cast(WatchFilter, 0) do
            fail Errors.BadParameterError{}
        let allocator = unwrap Swag.getContext().allocator
        let state     = cast(*WatcherNative, Memory.alloc(#sizeof(WatcherNative), allocator))
        Swag.init(state, 1)
        state.allocator = allocator
        defer if not .native do
            dropWatcherNative(state)
        state.descriptor = Linux.inotify_init1(Linux.IN_NONBLOCK | Linux.IN_CLOEXEC)
        if state.descriptor < 0 do
            try Errors.failLinuxError(Linux.errno(), .root)
        if Linux.pipe2(state.cancellation.buffer, Linux.O_NONBLOCK | Linux.O_CLOEXEC) != 0 do
            try Errors.failLinuxError(Linux.errno())
        state.buffer.reserve(.options.bufferSize)
        state.buffer.count = .options.bufferSize
        state.clock.start()
        try .addWatchTree(state, .root.toString())
        state.rootDescriptor = state.directories[0].descriptor
        .native = state
    }

    private mtd addWatchTree(state: *WatcherNative, root: string) fail
    {
        var paths: Array'String
        paths.add(root)
        while not paths.isEmpty()
        {
            var path       = paths.popBack()
            let native     = try Path.nativePath(path)
            let mask       = watchFilterNative(.options.filter) | Linux.IN_DONT_FOLLOW
            let descriptor = Linux.inotify_add_watch(state.descriptor, native.storage(), mask)
            if descriptor < 0 do
                try Errors.failLinuxError(Linux.errno(), path)
            for directory in state.directories
            {
                // Multiple directory paths can alias one inode through bind mounts.
                // Reject ambiguity rather than overwrite a watch's path or recurse forever.
                if directory.descriptor == descriptor do
                    try Errors.failLinuxError(Linux.ENOTSUP, path)
            }

            var directory: WatchedDirectory
            directory.descriptor = descriptor
            directory.path       = path
            state.directories.add(#move directory)
            if not .options.recurse do
                continue
            let entries = try enumerateOneNative(path)
            for entry in entries
            {
                let name = Path.fileName(entry.fullName) orelse ""
                if entry.isDirectory() and
                   name != "." and
                   name != ".." and
                   not entry.attributes.has(File.FileAttributes.ReparsePoint) do
                    paths.add(entry.fullName)
            }
        }
    }

    mtd cancelNative()
    {
        let state = watcherNative(.native)
        if state.cancelled.exchange(1) do
            return
        for
        {
            if Linux.write(state.cancellation[1], "x".buffer, 1) == 1 do
                return
            let error = Linux.errno()
            if error == Linux.EAGAIN do
                return
            if error != Linux.EINTR do
                Swag.panic("cannot wake the directory watcher", #curlocation)
        }
    }

    mtd closeNative()
    {
        if not .native do
            return
        let state = watcherNative(.native)
        .cancelNative()
        .native = null
        dropWatcherNative(state)
    }

    private mtd invalidateWatch()->WatchBatch
    {
        .cancelNative()
        return {status: .Overflow}
    }

    private mtd removeWatchTree(state: *WatcherNative, path: string)
    {
        var index = 0'u64
        while index < state.directories.count
        {
            if watchPathContains(path, state.directories[index].path.toString())
            {
                discard Linux.inotify_rm_watch(state.descriptor, state.directories[index].descriptor)
                state.directories.removeAt(index)
            }
            else
            {
                index += 1
            }
        }
    }

    private mtd parseWatchEvents(state: *WatcherNative, count: u64, batch: *WatchBatch)->bool fail
    {
        var offset = 0'u64
        while offset < count
        {
            if count - offset < #sizeof(Linux.inotify_event) do
                return false
            let event  = cast(const *Linux.inotify_event, state.buffer.storage() + offset)
            let length = #sizeof(Linux.inotify_event) + cast(u64, event.len)
            if length > count - offset do
                return false
            offset += length
            if (event.mask & (Linux.IN_Q_OVERFLOW | Linux.IN_UNMOUNT)) != 0 do
                return false
            if event.wd == state.rootDescriptor and
               (event.mask & (Linux.IN_DELETE_SELF | Linux.IN_MOVE_SELF | Linux.IN_IGNORED)) != 0 do
                return false
            var parent: String
            for directory in state.directories
            {
                if directory.descriptor == event.wd
                {
                    parent = directory.path
                    break
                }
            }

            if parent.isEmpty() do
                continue
            if (event.mask & Linux.IN_IGNORED) != 0
            {
                for directory, index in state.directories
                {
                    if directory.descriptor == event.wd
                    {
                        state.directories.removeAt(index)
                        break
                    }
                }

                continue
            }

            if event.len == 0 do
                continue
            let bytes      = state.buffer.storage() + offset - event.len
            var nameLength = 0'u64
            while nameLength < event.len and bytes[nameLength] != 0 do
                nameLength += 1
            if nameLength == event.len do
                return false
            let name      = cast(string, Swag.makeSlice(bytes, nameLength))
            let path      = Path.combine(parent, name)
            let directory = (event.mask & Linux.IN_ISDIR) != 0
            let report    = directory ? .options.filter.has(.DirectoryName) : .options.filter.has(.FileName)

            // A moved-out subtree can still emit events until its move is resolved.
            // Reusing a pending name would also put Added before the delayed Removed.
            // Report the gap rather than expose stale paths or reverse their event order.
            for move in state.moves
            {
                if move.path.toString() == path.toString() or
                   (directory and watchPathContains(path.toString(), move.path.toString())) or
                   (move.directory and watchPathContains(move.path.toString(), parent.toString())) do
                    return false
            }

            if (event.mask & Linux.IN_MOVED_FROM) != 0
            {
                var move: PendingWatchMove
                move.cookie    = event.cookie
                move.path      = path
                move.directory = directory
                move.report    = report
                move.expires   = state.clock.elapsedMilliseconds() + 50
                state.moves.add(#move move)
            }
            elif (event.mask & Linux.IN_MOVED_TO) != 0
            {
                var matched = false
                for move, index in state.moves
                {
                    if move.cookie != event.cookie do
                        continue
                    if directory != move.directory do
                        return false
                    if directory
                    {
                        for &watched in state.directories
                        {
                            if watchPathContains(move.path.toString(), watched.path.toString())
                            {
                                let suffix  = watched.path.toString()[move.path.count to]
                                var renamed = String.from(path.toString())
                                renamed      += suffix
                                watched.path = #move renamed
                            }
                        }
                    }

                    if report do
                        appendWatchChange(&batch.changes, .Renamed, path.toString(), move.path.toString())
                    state.moves.removeAt(index)
                    matched = true
                    break
                }

                if not matched
                {
                    if report do
                        appendWatchChange(&batch.changes, .Added, path.toString())
                    if directory and .options.recurse
                    {
                        try .addWatchTree(state, path.toString())
                        batch.status = .Overflow
                    }
                }
            }
            elif (event.mask & Linux.IN_CREATE) != 0
            {
                if report or .options.filter.has(.Creation) do
                    appendWatchChange(&batch.changes, .Added, path.toString())
                if directory and .options.recurse
                {
                    try .addWatchTree(state, path.toString())
                    batch.status = .Overflow
                }
            }
            elif (event.mask & Linux.IN_DELETE) != 0
            {
                if directory do
                    .removeWatchTree(state, path.toString())
                if report do
                    appendWatchChange(&batch.changes, .Removed, path.toString())
            }
            elif (event.mask & (Linux.IN_MODIFY | Linux.IN_ATTRIB | Linux.IN_ACCESS)) != 0
            {
                appendWatchChange(&batch.changes, .Modified, path.toString())
            }
        }

        return true
    }

    mtd nextNative(waitMilliseconds: u32)->WatchBatch fail
    {
        let state    = watcherNative(.native)
        let deadline = state.clock.elapsedMilliseconds() + cast(u64, waitMilliseconds)
        var batch: WatchBatch
        batch.status = .Changes

        // Any native failure makes the recursive subscription potentially incomplete.
        var completed = false
        defer if not completed do
            .cancelNative()
        for
        {
            if state.cancelled.load()
            {
                completed = true
                return {status: .Cancelled}
            }

            let received = Linux.read(state.descriptor, state.buffer.storage(), state.buffer.count)
            if received > 0
            {
                if not try .parseWatchEvents(state, cast(u64, received), &batch)
                {
                    completed = true
                    return .invalidateWatch()
                }

                if batch.status == .Overflow or not batch.changes.isEmpty()
                {
                    if batch.status == .Overflow do
                        batch.changes.clear()
                    completed = true
                    return batch
                }

                if waitMilliseconds != Swag.U32.Max and state.clock.elapsedMilliseconds() >= deadline
                {
                    completed = true
                    return {status: .TimedOut}
                }

                continue
            }

            if received == 0
            {
                completed = true
                return .invalidateWatch()
            }

            let error = Linux.errno()
            if error == Linux.EINTR do
                continue
            if error != Linux.EAGAIN do
                try Errors.failLinuxError(error, .root)
            let now       = state.clock.elapsedMilliseconds()
            var remaining = waitMilliseconds == Swag.U32.Max ? Swag.U64.Max : (now >= deadline ? 0'u64 : deadline - now)
            var index     = 0'u64
            while index < state.moves.count
            {
                let move = state.moves[index]
                if now >= move.expires
                {
                    if move.directory do
                        .removeWatchTree(state, move.path.toString())
                    if move.report do
                        appendWatchChange(&batch.changes, .Removed, move.path.toString())
                    state.moves.removeAt(index)
                }
                else
                {
                    if move.expires - now < remaining do
                        remaining = move.expires - now
                    index += 1
                }
            }

            if not batch.changes.isEmpty()
            {
                completed = true
                return batch
            }

            if remaining == 0
            {
                completed = true
                return {status: .TimedOut}
            }

            var fds: [2] Linux.pollfd
            fds[0] = {fd: state.descriptor, events: Linux.POLLIN}
            fds[1] = {fd: state.cancellation[0], events: Linux.POLLIN}
            let timeout = remaining == Swag.U64.Max ? -1's32 : cast(s32, Math.min(remaining, cast(u64, Swag.S32.Max)))
            let ready   = Linux.poll(fds.buffer, fds.count, timeout)
            if ready < 0
            {
                let pollError = Linux.errno()
                if pollError != Linux.EINTR do
                    try Errors.failLinuxError(pollError, .root)
            }
            else
            {
                for descriptor in fds do
                    if (descriptor.revents & (Linux.POLLERR | Linux.POLLHUP | Linux.POLLNVAL)) != 0 do
                        try Errors.failLinuxError(Linux.EBADF, .root)
            }
        }
    }
}
