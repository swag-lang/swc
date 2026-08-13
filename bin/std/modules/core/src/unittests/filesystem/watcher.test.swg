#global if #command == Swag.CompilerCommand.Test
#global if WINDOWS
#global private

struct CancelWatcherPayload
{
    watcher: *Directory.Watcher
}

func cancelWatcherThread(thread: Threading.Thread)
{
    let payload = cast(*CancelWatcherPayload) thread.userParam!
    Threading.Thread.sleep(Time.Duration.fromMilliseconds(50))
    payload.watcher.cancel()
}

func waitForWatchChange(watcher: *Directory.Watcher, kind: Directory.ChangeKind, path: string, oldPath: #null string = null)->bool fail
{
    for 12
    {
        let batch = watcher.next(500)
        if batch.status == .Overflow do
            return false
        if batch.status != .Changes do
            continue

        for change in batch.changes
        {
            let oldPathMatches = oldPath == null or change.oldPath.toString() == oldPath
            if change.kind == kind and change.path.toString() == path and oldPathMatches do
                return true
        }
    }

    return false
}

#test
{
    let root = CoreTests.makeFilesystemTestPath("core_directory_watcher")
    expect Directory.create(root)
    defer discard catch Directory.delete(root, recurse: true)

    var options: Directory.WatchOptions
    options.recurse = true
    var watcher = expect Directory.watch(root, options)

    let first = Path.combine(root, "before.txt")
    discard expect File.writeAllBytes(first, ['a'u8])
    @assert(expect waitForWatchChange(&watcher, .Added, first.toString()))

    let second = Path.combine(root, "after.txt")
    expect File.move(second, first)
    @assert(expect waitForWatchChange(&watcher, .Renamed, second.toString(), first.toString()))

    watcher.cancel()
    @assert((expect watcher.next(0)).status == .Cancelled)
    watcher.close()
}

#test
{
    let root = CoreTests.makeFilesystemTestPath("core_directory_watcher_cancel")
    expect Directory.create(root)
    defer discard catch Directory.delete(root, recurse: true)

    var watcher = expect Directory.watch(root)
    var payload = CancelWatcherPayload{watcher: &watcher}
    var thread: Threading.Thread
    expect thread.init(&cancelWatcherThread, &payload)
    expect thread.start()

    let batch = expect watcher.next()
    thread.wait()
    @assert(batch.status == .Cancelled)
}
