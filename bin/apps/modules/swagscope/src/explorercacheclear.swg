#global internal

using Core, Gui

// Clears Scope's persistent thumbnails and the shared in-memory music lookups after previews stop.
struct ExplorerCacheClear
{
    using operation: Viewer.BackgroundOperation
    removed: u64
    error:   String
    root:    String
}

impl ExplorerCacheClear
{
    mtd start(owner: *Wnd, root: string = "")
    {
        .removed = 0
        .error.clear()
        .root = root
        let operation = me
        .submit(func|operation|()
        {
            catch { operation.removed = try ThumbnailCache.clearAll(operation.root) }
            {
                operation.error = Viewer.failureText(Swag.err)
            }
            clearMusicCaches()
        }, owner)
    }

    mtd opDrop() { .wait() }
}
