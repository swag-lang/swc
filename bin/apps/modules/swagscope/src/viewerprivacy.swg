using Core, Gui, Pixel

private const VaultIcon = #include("../../swagvault/datas/appicon.png")

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
    scan:         ViewerPrivacyScan
    dirty:        bool
    cleanup:      Viewer.BackgroundOperation
    queue:        Array'String
    batch:        Array'String
    musicChoices: Array'MusicChoice
    folderViews:  Array'ExplorerFolderState
    caption:      *CaptionButton?
    icons:        ImageList
}

impl ViewerPrivacy
{
    mtd createIndicator()
    {
        .caption = CaptionButton.createLeading(unwrap .window.surface, .Lock)
        .caption.hide()
    }

    // Reuse Vault's actual mark as a tintable mask; its tile and background stay out of the strip.
    private mtd createIcon()
    {
        var source = expect Image.decode(".png", VaultIcon)
        source.resize(64, 64, .Bilinear)
        var mask      = Image.create(64, 64, .RGBA8)
        var left: s32 = 64
        var top:  s32 = 64
        var right, bottom: s32
        for y in 64
        {
            for x in 64
            {
                let color = source.pixelColor(x, y)
                let level = cast(s32, Math.max(color.r, Math.max(color.g, color.b)))
                let alpha = cast(u8, Math.clamp((level - 32) * 255 / 160, 0, 255))

                // Image coordinates start at the top; packed image rows start at the bottom.
                let pixel = mask.pixels.storage() + cast(u64, (63 - y) * mask.rowStride + x * 4)
                pixel[0] = 255
                pixel[1] = 255
                pixel[2] = 255
                pixel[3] = alpha
                if alpha > 32
                {
                    left   = Math.min(left, x)
                    top    = Math.min(top, y)
                    right  = Math.max(right, x)
                    bottom = Math.max(bottom, y)
                }
            }
        }

        mask.crop(left, top, right - left + 1, bottom - top + 1)
        .icons = ImageList.create(.window.app().renderer.addImage(&mask))
    }

    mtd refreshIndicator()
    {
        if not .caption do
            return
        if not .window.isWorkspaceActive()
        {
            .caption.hide()
            return
        }
        let path        = .window.isExploring() ? .window.explorer!.listing.path.toString() : .window.currentFile.toString()
        let privateMode = path.count and .policy(path).privateMode
        .caption.toolTip = appStrings().ui_PrivateVault
        if privateMode
        {
            if not .icons.isValid() do
                .createIcon()
            let size  = .window.themeMetrics().wnd_CaptionButtonGlyph
            let width = size * cast(f32, .icons.frameWidth) / cast(f32, .icons.frameHeight)
            .caption.button.setIcon(Icon.from(&.icons, 0, width, size))
            .caption.setIconColor(.window.themeColors().critical)
        }

        .caption.show(privateMode and not .window.fullScreen)
    }

    mtd destroyIndicator()
    {
        .caption?.destroy()
        .caption = null
        .icons.release(.window.app().renderer)
    }

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

    // Removes durable bookmarks and blocks the current panels from re-adding this activation.
    private mtd forgetTextBookmarks(path: string)
    {
        for index in reversed(.window.textBookmarkFiles.count) where
            Path.equals(.window.textBookmarkFiles[index].path, path) do
            .window.textBookmarkFiles.removeAtOrdered(index)

        for instance in .window.instances
        {
            if instance.view is Viewers.PlainText.Panel as view where Path.equals(view.fileName, path) do
                view.bookmarksPersistable = false
        }
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
            .forgetTextBookmarks(source.path)
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
        .scan.task.cancel()
        .scan.wait()
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

    private mtd knows(path: string)->bool
    {
        for &source in .sources where Path.equals(source.path, path) do
            return true
        return not path.count
    }

    // Unresolved saved paths remain in memory, but cannot be persisted until their policy arrives.
    private mtd mayPersist(path: string)->bool => .knows(path) and not .forgetPrivatePath(path)

    private mtd queueSource(path: string)
    {
        if .knows(path) do
            return
        for &source in .scan.sources where Path.equals(source.path, path) do
            return
        .scan.sources.add({path: path})
    }

    // Loading or saving history never opens its paths, including aliases and disconnected drives.
    mtd sanitize()
    {
        discard .refresh()
        if .scan.started do
            return
        .scan.sources.clear()
        for &path in .window.recent do
            .queueSource(path[])
        for &entry in .window.folderHistory do
            .queueSource(entry.file)
        for &path in .window.exploredFolders do
            .queueSource(path[])
        for &state in .window.folderViews do
            .queueSource(state.path)
        for &entry in .window.musicChoices do
            .queueSource(entry.path)
        for &point in .window.resumePoints do
            .queueSource(point.file)
        .queueSource(.window.fileDlgState.currentFolder)
        for &path in .window.fileDlgState.recentFolders do
            .queueSource(path[])
        .scan.start(.window)
    }

    mtd finishScan()
    {
        .scan.wait()
        for &source in .scan.sources where not .knows(source.path) do
            .track(source.path, source.policy)
        .scan.sources.clear()
        .dirty = true
        .sanitize()
    }

    // Serialize verified copies; filtering must not erase unresolved entries from the live window.
    mtd serializeState(serializer: *Serialization.Serializer)
    {
        let window  = .window
        var recent  = window.recent
        var opened  = window.recentOpened
        var folders = window.exploredFolders
        var history = window.folderHistory
        var views   = window.folderViews
        var music   = window.musicChoices
        var resume  = window.resumePoints
        var textBookmarkFiles = window.textBookmarkFiles
        var dialog  = window.fileDlgState
        if not serializer.isReading()
        {
            opened.resize(recent.count)
            for index in reversed(recent.count) where not .mayPersist(recent[index])
            {
                recent.removeAtOrdered(index)
                opened.removeAtOrdered(index)
            }

            for index in reversed(folders.count) where not .mayPersist(folders[index]) do
                folders.removeAtOrdered(index)
            for index in reversed(history.count) where not .mayPersist(history[index].file) do
                history.removeAtOrdered(index)
            for index in reversed(views.count) where not .mayPersist(views[index].path) do
                views.removeAtOrdered(index)
            for index in reversed(music.count) where not .mayPersist(music[index].path) do
                music.removeAtOrdered(index)
            for index in reversed(resume.count) where not .mayPersist(resume[index].file) do
                resume.removeAtOrdered(index)
            while textBookmarkFiles.count > ViewerTextBookmarkFileLimit do
                textBookmarkFiles.removeAtOrdered(0)
            for &record in textBookmarkFiles
            {
                while record.bookmarks.count > ViewerTextBookmarkLimit do
                    record.bookmarks.removeAtOrdered(0)
                .track(record.path)
            }
            for index in reversed(textBookmarkFiles.count) where not .mayPersist(textBookmarkFiles[index].path) do
                textBookmarkFiles.removeAtOrdered(index)
            if not .mayPersist(dialog.currentFolder) do
                dialog.currentFolder.clear()
            for index in reversed(dialog.recentFolders.count) where not .mayPersist(dialog.recentFolders[index]) do
                dialog.recentFolders.removeAtOrdered(index)
        }

        catch serializer.serialize("ViewerWindow.fileDlgState", &dialog)
        catch serializer.serialize("ViewerWindow.recent", &recent)
        catch serializer.serialize("ViewerWindow.recentOpened", &opened)
        catch serializer.serialize("ViewerWindow.folderHistory", &history)
        catch serializer.serialize("ViewerWindow.resumePoints", &resume)
        catch serializer.serialize("ViewerWindow.exploredFolders", &folders)
        catch serializer.serialize("ViewerWindow.folderViews", &views)
        catch serializer.serialize("ViewerWindow.musicChoices", &music)
        catch serializer.serialize("ViewerWindow.textBookmarkFiles", &textBookmarkFiles)
        if serializer.isReading()
        {
            for index in reversed(textBookmarkFiles.count) where
                textBookmarkFiles[index].path.isEmpty() or textBookmarkFiles[index].identity.isEmpty() or
                textBookmarkFiles[index].bookmarks.isEmpty() do
                textBookmarkFiles.removeAtOrdered(index)
            while textBookmarkFiles.count > ViewerTextBookmarkFileLimit do
                textBookmarkFiles.removeAtOrdered(0)
            for &record in textBookmarkFiles
            {
                while record.bookmarks.count > ViewerTextBookmarkLimit do
                    record.bookmarks.removeAtOrdered(0)
            }

            window.fileDlgState    = #move dialog
            window.recent          = #move recent
            window.recentOpened    = #move opened
            window.folderHistory   = #move history
            window.resumePoints    = #move resume
            window.textBookmarkFiles = #move textBookmarkFiles
            window.exploredFolders = #move folders
            window.folderViews     = #move views
            window.musicChoices    = #move music
        }
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
