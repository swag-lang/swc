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

    // Keeps folders first, then orders the members by the chosen field and naturally by name.
    mtd sortEntries()
    {
        let operation = me
        .result.entries.sort(func|operation|(a, b)->s32
        {
            if a.directory != b.directory do
                return a.directory ? -1 : 1
            var order: s32
            switch operation.sortColumn
            {
            case 1: order = Latin1.compareNatural(Path.extension(a.name) orelse "",
                                                  Path.extension(b.name) orelse "")

            case 2:  order = a.size == b.size ? 0 : (a.size < b.size ? -1 : 1)
            case 3:  order = Latin1.compareNatural(a.modified, b.modified)
            default: order = Latin1.compareNatural(a.name, b.name)
            }

            if order == 0 do
                order = Latin1.compareNatural(a.name, b.name)
            return operation.descending ? -order : order
        })
    }

    mtd finish(result: *ExplorerListing)->String
    {
        .wait()
        result[] = #move .result
        return #move .error
    }

    mtd opDrop() { .wait() }
}
