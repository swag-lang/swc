#global public
#global namespace Directory

// Filesystem properties that can cause a watcher notification.
#[Swag.EnumFlags]
enum WatchFilter
{
    FileName                                                            // File creation, deletion, and rename.
    DirectoryName                                                       // Directory creation, deletion, and rename.
    Attributes                                                          // Attribute changes.
    Size                                                                // File size changes.
    LastWrite                                                           // Last-write time changes.
    LastAccess                                                          // Last-access time changes.
    Creation                                                            // Creation-time changes.
    Security                                                            // Security descriptor changes.
    Common = FileName | DirectoryName | Size | LastWrite                // Changes commonly used by build and editor tools.
    All    = Common | Attributes | LastAccess | Creation | Security     // Every portable notification category.
}

// Kind of one normalized filesystem change.
enum ChangeKind
{
    Added        // A path appeared.
    Removed      // A path disappeared.
    Modified     // A watched property changed.
    Renamed      // One path was renamed; both `oldPath` and `path` are populated.
}

// Outcome of one [[Core.Directory.Watcher.next]] call.
enum WatchStatus
{
    Changes       // One or more normalized changes are available.
    TimedOut      // The wait duration elapsed; the pending host request remains active.
    Overflow      // Host notifications were lost; the caller must rescan the watched tree.
    Cancelled     // [[Core.Directory.Watcher.cancel]] stopped the stream permanently.
}

// One normalized change reported by a directory watcher.
struct Change
{
    public
    {
        kind:    ChangeKind     // Operation represented by this value.
        path:    String         // Full path after the change, or the removed path.
        oldPath: String         // Full path before a rename; empty for other kinds.
    }
}

// One completed watcher read.
struct WatchBatch
{
    public
    {
        status:  WatchStatus      // Outcome that determines how the caller should continue.
        changes: Array'Change     // Normalized changes; populated only for `Changes`.
    }
}

// Options used to create a [[Core.Directory.Watcher]].
struct WatchOptions
{
    public
    {
        filter     = WatchFilter.Common     // Properties that produce notifications.
        recurse    = false                  // Whether descendants of the watched directory are included.
        bufferSize = 64 * 1024'u32          // Native notification buffer in bytes, from 4 KiB through 64 KiB.
    }
}

// Owns a cancellable stream of filesystem changes for one directory tree.
//
// [[Core.Directory.Watcher.next]] has at most one outstanding host read. A timeout preserves that
// request, so the next call continues waiting without a notification gap. `cancel` may be called
// from another thread and permanently changes subsequent reads to `Cancelled`. `close` releases
// resources and must not race with `next` or another `close`.
#[Swag.NoCopy]
struct Watcher
{
    public readonly
    {
        root:    String           // Normalized directory whose changes are reported.
        options: WatchOptions     // Scope, filter, and buffer policy fixed at creation.
    }

    internal native: *void?
}

// Starts watching `root` with the default options.
func watch(root: string)->Watcher fail
{
    var options: WatchOptions
    return watch(root, options)
}

// Starts watching `root` with an explicit scope and notification policy.
func watch(root: string, options: WatchOptions)->Watcher fail
{
    if options.bufferSize < 4 * 1024 or options.bufferSize > 64 * 1024 do
        fail Errors.BadParameterError{}

    var result: retval
    result.root    = Path.absolute(root)
    result.options = options
    result.openNative()
    return result
}

impl Watcher
{
    // Releases the watcher and cancels an outstanding read. Repeated calls do nothing.
    mtd close()
    {
        .closeNative()
    }

    // Releases the watcher and cancels an outstanding read.
    mtd opDrop()
    {
        .close()
    }

    // Returns whether this value owns an open host watcher.
    mtd const isOpen()->bool => .native != null

    // Permanently cancels the stream and wakes a thread blocked in [[Core.Directory.Watcher.next]].
    //
    // This is the only method that may safely run concurrently with `next`. Repeated calls do
    // nothing. The watcher remains owned until `close` or automatic destruction.
    mtd cancel()
    {
        if .native do
            .cancelNative()
    }

    // Waits for the next batch of filesystem changes.
    //
    // `waitMilliseconds` is zero for polling and [[Swag.U32.Max]] for an unbounded wait. Rename
    // records split by host buffer boundaries are paired across calls. `Overflow` means paths may
    // have changed without a corresponding record and requires a complete rescan.
    mtd next(waitMilliseconds = Swag.U32.Max)->WatchBatch fail
    {
        Debug.assert(.isOpen())
        return .nextNative(waitMilliseconds)
    }
}
