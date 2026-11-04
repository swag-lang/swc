#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#[Swag.TestTag("integration.watcher")]
#test
{
    let root = CoreTests.makeFilesystemTestPath("core_watcher_new_subtree")
    expect Directory.create(root)
    defer discard catch Directory.delete(root, recurse: true)
    var watcher = expect Directory.watch(root, {recurse: true})
    let child   = Path.combine(root, "new")
    expect Directory.create(child)

    // Linux cannot atomically subscribe to a new directory and its existing contents.
    // Overflow requests a rescan, but the newly installed subscription remains usable.
    Swag.require((expect watcher.next(1000)).status == .Overflow)
    let file = Path.combine(child, "observed")
    discard expect File.writeAllBytes(file, ['x'u8])
    Swag.require(expect waitForWatchChange(&watcher, .Added, file.toString()))
}

#[Swag.TestTag("integration.watcher")]
#test
{
    let root = CoreTests.makeFilesystemTestPath("core_watcher_root_removed")
    expect Directory.create(root)
    defer discard catch Directory.delete(root, recurse: true)
    var watcher = expect Directory.watch(root)
    expect Directory.delete(root)
    Swag.require((expect watcher.next(1000)).status == .Overflow)
    Swag.require((expect watcher.next(0)).status == .Cancelled)
}

#[Swag.TestTag("integration.watcher")]
#test
{
    let root    = CoreTests.makeFilesystemTestPath("core_watcher_move_out")
    let outside = CoreTests.makeFilesystemTestPath("core_watcher_moved_file")
    expect Directory.create(root)
    defer discard catch Directory.delete(root, recurse: true)
    defer discard catch File.delete(outside)
    let original = Path.combine(root, "original")
    discard expect File.writeAllBytes(original, ['x'u8])
    var watcher = expect Directory.watch(root, {filter: .FileName})
    expect File.move(outside, original)

    // An unmatched move is eventually Removed; it must not wait for another filesystem event.
    Swag.require(expect waitForWatchChange(&watcher, .Removed, original.toString()))
    Swag.require((expect watcher.next(0)).status == .TimedOut)
}

#[Swag.TestTag("integration.watcher")]
#test
{
    let root    = CoreTests.makeFilesystemTestPath("core_watcher_links")
    let outside = CoreTests.makeFilesystemTestPath("core_watcher_link_target")
    expect Directory.create(root)
    expect Directory.create(outside)
    defer discard catch Directory.delete(root, recurse: true)
    defer discard catch Directory.delete(outside, recurse: true)
    let link         = Path.combine(root, "link")
    let linkNative   = expect Path.nativePath(link)
    let targetNative = expect Path.nativePath(outside)
    let linked       = Linux.symlinkat(targetNative.storage(), Linux.AT_FDCWD, linkNative.storage())
    Swag.require(linked == 0)
    var watcher = expect Directory.watch(root, {recurse: true})
    let file    = Path.combine(outside, "unobserved")
    discard expect File.writeAllBytes(file, ['x'u8])
    Swag.require((expect watcher.next(20)).status == .TimedOut)
    var error: Swag.Error
    discard catch Directory.watch(link) as error
    Swag.require(error.value() != null)
}

#[Swag.TestTag("integration.watcher")]
#test
{
    let root    = CoreTests.makeFilesystemTestPath("core_watcher_move_reuse")
    let outside = CoreTests.makeFilesystemTestPath("core_watcher_move_reuse_outside")
    expect Directory.create(root)
    defer discard catch Directory.delete(root, recurse: true)
    defer discard catch File.delete(outside)
    let original = Path.combine(root, "original")
    discard expect File.writeAllBytes(original, ['x'u8])
    var watcher = expect Directory.watch(root, {filter: .FileName})
    expect File.move(outside, original)
    discard expect File.writeAllBytes(original, ['y'u8])

    // Do not emit Added followed later by Removed for a name which still exists.
    Swag.require((expect watcher.next(1000)).status == .Overflow)
    Swag.require((expect watcher.next(0)).status == .Cancelled)
}

#[Swag.TestTag("integration.watcher")]
#test
{
    let root    = CoreTests.makeFilesystemTestPath("core_watcher_move_parent")
    let child   = Path.combine(root, "child")
    let outside = CoreTests.makeFilesystemTestPath("core_watcher_move_parent_outside")
    expect Directory.create(child, recurse: true)
    defer discard catch Directory.delete(root, recurse: true)
    defer discard catch File.delete(outside)
    let original = Path.combine(child, "original")
    discard expect File.writeAllBytes(original, ['x'u8])
    var watcher = expect Directory.watch(root, {recurse: true})
    expect File.move(outside, original)
    expect Directory.delete(child)

    // Parent removal must not be followed by a delayed removal at an obsolete child path.
    Swag.require((expect watcher.next(1000)).status == .Overflow)
    Swag.require((expect watcher.next(0)).status == .Cancelled)
}
