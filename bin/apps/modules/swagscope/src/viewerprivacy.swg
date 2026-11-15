using Core

// Retains provenance in memory even when the mount disappears or an archive is extracted.
struct ViewerPrivacySource
{
    path:   String
    policy: File.MountPrivacy
    forget: bool
}

// Owns the retention policy and cleanup work for one Scope window.
struct ViewerPrivacy
{
    late window:  *ViewerWindow
    sources:      Array'ViewerPrivacySource
    dirty:        bool
    cleanup:      Viewer.BackgroundOperation
    queue:        Array'String
    batch:        Array'String
    musicChoices: Array'MusicChoice
    folderViews:  Array'ExplorerFolderState
}

impl ViewerPrivacy
{
    mtd track(path: string, policy: File.MountPrivacy)
    {
        if not path.count do
            return
        for &source in .sources where Path.equals(source.path, path)
        {
            // A vanished mount or an extracted temporary must not erase its provenance.
            if not policy.root.isEmpty() and
               (source.policy.root.isEmpty() or
                source.policy.instance != policy.instance or
                source.policy.channel != policy.channel)
            {
                source.forget = true
                source.policy = policy
            }

            return
        }

        .sources.add({path: path, policy: policy, forget: policy.privateMode})
    }

    mtd track(path: string)
    {
        if not path.count do
            return
        for &source in .sources where Path.equals(source.path, path) do
            return
        .track(path, File.MountPrivacy.query(path))
    }

    // A worker receives its own copy, including the provenance of nested archive extractions.
    mtd policy(path: string)->File.MountPrivacy
    {
        .track(path)
        for &source in .sources where Path.equals(source.path, path) do
            return source.policy
        return {}
    }

    mtd inherit(path, origin: string)
    {
        var inherited = .policy(origin)
        .track(path, #move inherited)
    }

    private mtd forgetPrivatePath(path: string)->bool
    {
        for &source in .sources where Path.equals(source.path, path) do
            return source.forget or source.policy.privateMode
        return false
    }

    // Reconcile before every persistence boundary as well as while the window is idle.
    // Polling existing publications never reopens the user's files or folders.
    mtd refresh()->bool
    {
        var changed = false
        var refreshed: Array'File.MountPrivacy
        for &source in .sources where not source.policy.root.isEmpty()
        {
            var policy = source.policy
            var found  = false
            for &current in refreshed where current.channel == policy.channel and current.instance == policy.instance
            {
                policy = current[]
                found  = true
                break
            }

            if not found
            {
                discard policy.refresh()
                refreshed.add(policy)
            }

            if policy.privateMode and not source.policy.privateMode or policy.activation != source.policy.activation or policy.instance != source.policy.instance
            {
                source.forget = true
                changed       = true
            }

            source.policy = policy
        }

        // Every alias and extracted member of the same mount belongs to the activation.
        for &source in .sources where source.forget
        {
            for &other in .sources where other.policy.channel == source.policy.channel do
                other.forget = true
            .queueCacheClear(source.policy.channel)
        }

        .window.recentOpened.resize(.window.recent.count)
        for index in reversed(.window.recent.count) where .forgetPrivatePath(.window.recent[index])
        {
            .window.recent.removeAtOrdered(index)
            .window.recentOpened.removeAtOrdered(index)
            changed = true
        }

        for index in reversed(.window.folderHistory.count) where .forgetPrivatePath(.window.folderHistory[index].file) do
            .window.folderHistory.removeAtOrdered(index)
        for index in reversed(.window.exploredFolders.count) where .forgetPrivatePath(.window.exploredFolders[index]) do
            .window.exploredFolders.removeAtOrdered(index)
        for index in reversed(.window.folderViews.count) where .forgetPrivatePath(.window.folderViews[index].path)
        {
            .keepFolderView(&.folderViews, .window.folderViews[index])
            .window.folderViews.removeAtOrdered(index)
        }

        for index in reversed(.window.resumePoints.count) where .forgetPrivatePath(.window.resumePoints[index].file) do
            .window.resumePoints.removeAtOrdered(index)
        for index in reversed(.window.musicChoices.count) where .forgetPrivatePath(.window.musicChoices[index].path)
        {
            .keepMusicChoice(.window.musicChoices[index])
            .window.musicChoices.removeAtOrdered(index)
        }

        if .forgetPrivatePath(.window.fileDlgState.currentFolder) do
            .window.fileDlgState.currentFolder.clear()
        for index in reversed(.window.fileDlgState.recentFolders.count) where .forgetPrivatePath(.window.fileDlgState.recentFolders[index]) do
            .window.fileDlgState.recentFolders.removeAtOrdered(index)
        for &source in .sources where source.forget
        {
            if .window.explorer and Path.equals(.window.explorer.listing.path, source.path) do
                .window.explorer.privateView = true
            changed       = true
            source.forget = false
        }

        .dirty = .dirty or changed
        return changed
    }

    // Complete all pending cleanup before the window and its worker state are released.
    mtd flush()
    {
        while .cleanup.started or not .queue.isEmpty()
        {
            .cleanup.wait()
            .clearCaches()
        }
    }

    mtd opDrop() { .flush() }

    mtd mayRemember(path: string)->bool
    {
        .track(path)
        discard .refresh()
        return not .forgetPrivatePath(path)
    }

    // Private matches remain usable in this window, without becoming serialized preferences.
    mtd selectedMusicId(entry: const *ExplorerEntry)->string
    {
        let transient = musicChoiceId(.musicChoices.toSlice(), entry)
        if transient.count do
            return transient
        return musicChoiceId(.window.musicChoices.toSlice(), entry)
    }

    mtd rememberMusicChoice(entry: const *ExplorerEntry, id, origin: string)
    {
        let retain = .mayRemember(origin)
        setMusicChoice(&.musicChoices, entry, "")
        if retain do
            setMusicChoice(&.window.musicChoices, entry, id)
        else do
            setMusicChoice(&.musicChoices, entry, id)
    }

    // Private locations remain navigable in this window without entering serialized state.
    mtd rememberFolderView(state: ExplorerFolderState, transient = false)
    {
        let retain = .mayRemember(state.path) and not transient
        let views  = retain ? &.window.folderViews : &.folderViews
        let other  = retain ? &.folderViews : &.window.folderViews
        for index in reversed(other.count) where other[index].matches(state.path, state.folder) do
            other.removeAtOrdered(index)
        .keepFolderView(views, state)
    }

    private mtd keepFolderView(views: *Array'ExplorerFolderState, state: ExplorerFolderState)
    {
        for &existing in views[] where existing.matches(state.path, state.folder)
        {
            existing[] = state
            return
        }

        if views.count >= 256 do
            views.removeAtOrdered(0)
        views.add(state)
    }

    mtd folderView(path, folder: string)->const *ExplorerFolderState?
    {
        .track(path)
        discard .refresh()
        for &state in .folderViews where state.matches(path, folder) do
            return state
        for &state in .window.folderViews where state.matches(path, folder) do
            return state
        return null
    }

    private mtd keepMusicChoice(choice: MusicChoice)
    {
        for &existing in .musicChoices where existing.path == choice.path do
            return
        if .musicChoices.count >= 1000 do
            .musicChoices.removeAtOrdered(0)
        .musicChoices.add(choice)
    }

    // Loaded history and dialog state can refer to mounts the current document has never used.
    mtd sanitize()
    {
        for &path in .window.recent do
            .track(path[])
        for &entry in .window.folderHistory do
            .track(entry.file)
        for &path in .window.exploredFolders do
            .track(path[])
        for &state in .window.folderViews do
            .track(state.path)
        for &entry in .window.musicChoices do
            .track(entry.path)
        .track(.window.fileDlgState.currentFolder)
        for &path in .window.fileDlgState.recentFolders do
            .track(path[])
        discard .refresh()
    }

    private mtd queueCacheClear(channel: string)
    {
        if channel.count and not .queue.contains(channel) do
            .queue.add(channel)
    }

    mtd clearCaches()
    {
        if .cleanup.started
        {
            if not .cleanup.isDone() do
                return
            .cleanup.wait()
        }

        if .queue.isEmpty() do
            return
        .batch = #move .queue
        let privacy = me
        .cleanup.submit(func|privacy|()
        {
            for &channel in privacy.batch do
                catch ThumbnailCache.clearMount(channel[])
            clearMusicCaches()
        })
    }
}
