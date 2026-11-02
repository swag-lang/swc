#global if #command == Swag.CompilerCommand.Test
#global private

struct CancelWatcherPayload
{
    watcher: *Directory.Watcher
}

func cancelWatcherThread(thread: const *Threading.Thread)
{
    let payload = cast(*CancelWatcherPayload, unwrap thread.userParam)
    Threading.Thread.sleep(Time.Duration.fromMilliseconds(50))
    payload.watcher.cancel()
}

internal func waitForWatchChange(watcher: *Directory.Watcher, kind: Directory.ChangeKind, path: string, oldPath: string? = null)->bool fail
{
    for 12
    {
        let batch = try watcher.next(500)
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

#[Swag.TestTag("integration.watcher")]
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
    Swag.assert(expect waitForWatchChange(&watcher, .Added, first.toString()))

    let second = Path.combine(root, "after.txt")
    expect File.move(second, first)
    Swag.assert(expect waitForWatchChange(&watcher, .Renamed, second.toString(), first.toString()))

    watcher.cancel()
    Swag.assert((expect watcher.next(0)).status == .Cancelled)
    watcher.close()
}

#[Swag.TestTag("integration.watcher")]
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

    let batch = expect watcher.next(5000)
    thread.wait()
    Swag.assert(batch.status == .Cancelled)
    watcher.cancel()
    Swag.assert((expect watcher.next(0)).status == .Cancelled)
    watcher.close()
    watcher.close()
    Swag.assert(not watcher.isOpen())
}

#[Swag.TestTag("integration.watcher")]
#test
{
    let root = CoreTests.makeFilesystemTestPath("core_directory_watcher_timeout")
    expect Directory.create(root)
    defer discard catch Directory.delete(root, recurse: true)
    var watcher = expect Directory.watch(root, {filter: .FileName})
    Swag.assert((expect watcher.next(0)).status == .TimedOut)
    Swag.assert((expect watcher.next(20)).status == .TimedOut)
    let file = Path.combine(root, "after-timeout")
    discard expect File.writeAllBytes(file, ['x'u8])
    Swag.assert(expect waitForWatchChange(&watcher, .Added, file.toString()))
    discard expect File.writeAllBytes(file, ['y'u8])
    Swag.assert((expect watcher.next(20)).status == .TimedOut)
}

#[Swag.TestTag("integration.watcher")]
#test
{
    let root   = CoreTests.makeFilesystemTestPath("core_directory_watcher_recursive")
    let child  = Path.combine(root, "before")
    let nested = Path.combine(child, "nested")
    expect Directory.create(nested)
    defer discard catch Directory.delete(root, recurse: true)
    var watcher = expect Directory.watch(root, {recurse: true})
    let first   = Path.combine(nested, "first")
    discard expect File.writeAllBytes(first, ['x'u8])
    Swag.assert(expect waitForWatchChange(&watcher, .Added, first.toString()))
    let renamed = Path.combine(root, "after")
    expect File.move(renamed, child)
    Swag.assert(expect waitForWatchChange(&watcher, .Renamed, renamed.toString(), child.toString()))
    let second = Path.combine(renamed, "nested/second")
    discard expect File.writeAllBytes(second, ['y'u8])
    Swag.assert(expect waitForWatchChange(&watcher, .Added, second.toString()))
}
