using Core, Gui

// Checks only an explicitly requested snapshot, on a thread independent of document loading.
struct ViewerHistoryCleanup
{
    using operation: Viewer.BackgroundOperation
    executor:        Swag.Executor
    recent:          Array'String
    opened:          Array'u64
    folders:         Array'String
    missing:         Array'String
    missingFolders:  Array'String
}

impl ViewerHistoryCleanup
{
    mtd start(window: *ViewerWindow)
    {
        if .started do
            return
        window.recentOpened.resize(window.recent.count)
        .recent  = window.recent
        .opened  = window.recentOpened
        .folders = window.exploredFolders
        .missing.clear()
        .missingFolders.clear()
        if not .executor.isStarted() do
            .executor.start(.Background)
        let cleanup = me
        .submit(func|cleanup|()
        {
            for path in cleanup.recent where not Swag.isCancelled() and not File.exists(path[]) do
                cleanup.missing.add(path[])
            for path in cleanup.folders where not Swag.isCancelled() and not Directory.exists(path[]) do
                cleanup.missingFolders.add(path[])
        },
                window,
                executor: &.executor)
    }

    // A later open or edit supersedes this scan; it cannot delete newly remembered entries.
    mtd finish(window: *ViewerWindow)
    {
        .wait()
        if window.recent.count != .recent.count or
           window.recentOpened.count != .opened.count or
           window.exploredFolders.count != .folders.count do
            return
        for path, index in .recent where path != window.recent[index] or .opened[index] != window.recentOpened[index] do
            return
        for path, index in .folders where path != window.exploredFolders[index] do
            return

        for index in reversed(window.recent.count) where .missing.contains(window.recent[index])
        {
            window.recent.removeAtOrdered(index)
            window.recentOpened.removeAtOrdered(index)
        }

        for index in reversed(window.exploredFolders.count) where .missingFolders.contains(window.exploredFolders[index]) do
            window.exploredFolders.removeAtOrdered(index)
        window.historyChanged()
    }

    mtd opDrop()
    {
        .task.cancel()
        .wait()
        .executor.close()
    }
}
