#global internal

using Core, Gui

// Enumerates, projects archive children and sorts on a worker; publication only transfers ownership.
struct ExplorerListingLoad
{
    using operation: Viewer.BackgroundOperation
    path:            String
    folder:          String
    result:          ExplorerListing
    error:           String
    sortColumn:      u32
    descending:      bool
    watcher:         Directory.Watcher
    restartWatch:    bool
}

impl ExplorerListingLoad
{
    mtd start(path, folder: string, sortColumn: u32, descending: bool, owner: *Wnd)
    {
        let replaceWatch = .restartWatch or .path != path or not .watcher.isOpen()
        .path         = path
        .folder       = folder
        .sortColumn   = sortColumn
        .descending   = descending
        .restartWatch = false
        .error.clear()
        let operation = me
        .submit(func|operation, replaceWatch|()
        {
            // Subscribe before enumerating so changes during the scan can trigger another one.
            if replaceWatch
            {
                operation.watcher.close()
                if Directory.exists(operation.path) do
                    operation.watcher = catch Directory.watch(operation.path) orelse {}
            }

            catch
            {
                operation.result = try ExplorerListing.load(operation.path)
                if operation.result.isArchive do
                    operation.result.entries = operation.result.children(operation.folder)
                operation.sortEntries()
            }
            {
                operation.error = Viewer.failureText(Swag.err)
            }
        },
                owner)
    }

    // Polled only while the listing worker is idle, so the stream has one owner at a time.
    mtd pollChanges()->bool
    {
        let batch = catch .watcher.next(0)
        {
            .restartWatch = true
            return true
        }

        .restartWatch = batch.status == .Overflow or batch.status == .Cancelled
        return .restartWatch or not batch.changes.isEmpty()
    }

    mtd sortEntries()
    {
        let column     = .sortColumn
        let descending = .descending
        .result.entries.sort(func|column, descending|(a, b)->s32 => a.compareForSort(&b, column, descending))
    }

    mtd finish(result: *ExplorerListing)->String
    {
        .wait()
        result[] = #move .result
        return #move .error
    }

    mtd opDrop() { .wait() }
}
