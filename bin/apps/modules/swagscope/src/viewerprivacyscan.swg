using Core, Gui

// Resolves saved paths away from the GUI and the document-loading worker pool.
struct ViewerPrivacyScan
{
    using operation: Viewer.BackgroundOperation
    executor:        Swag.Executor
    sources:         Array!{ViewerPrivacySource}
}

impl ViewerPrivacyScan
{
    mtd start(owner: *Wnd)
    {
        if .sources.isEmpty()
        {
            return
        }

        if not .executor.isStarted()
        {
            .executor.start(.Background)
        }

        let scan = me
        .submit(func|scan|()
        {
            for &source in scan.sources
            {
                if Swag.isCancelled()
                {
                    return
                }

                source.policy = File.MountPrivacy.query(source.path)
            }
        },
                owner,
                executor: &.executor)
    }

    mtd opDrop()
    {
        .task.cancel()
        .wait()
        .executor.close()
    }
}
