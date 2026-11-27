impl ViewerWindow
{
    private mtd const isFolderReading()->bool => .playMode == .Folder or .playMode == .Shuffle

    // Returns the progress rendering and shuffle choice to their neutral state.
    private mtd resetFolderReading()
    {
        .folderReadingMode = .Once
        .folderReadingFolder.clear()
        .folderReadingFiles.clear()
    }

    // Starts or advances one folder round, resetting it when its mode or folder changes.
    private mtd trackFolderReading(mode: Viewer.PlayMode)
    {
        if (mode != .Folder and mode != .Shuffle) or .currentFile.isEmpty()
        {
            return
        }

        let folder = Path.directoryName(.currentFile) orelse ""
        if .folderReadingMode != mode or Utf8.compare(.folderReadingFolder.toSlice(), folder, .Latin1NoCase) != 0
        {
            .folderReadingMode   = mode
            .folderReadingFolder = folder
            .folderReadingFiles.clear()
        }

        if not .folderReadingFiles.contains(.currentFile)
        {
            .folderReadingFiles.add(.currentFile)
        }
    }

    // Queues the file that follows the current one in `mode` among those its viewer opens, and
    // reports whether there was one to queue.
    //
    // A file that a play mode brings up is not one the reader chose, so it joins neither the
    // recent list nor the folder history.
    mtd continueFile(mode: Viewer.PlayMode, autoplayScene = false)->bool
    {
        if .currentFile.isEmpty()
        {
            return false
        }

        .trackFolderReading(mode)
        var files = .kindSiblings()
        if autoplayScene and .workspace
        {
            for index in reversed(files.count) where .workspace.isOpenInAnotherView(me, files[index])
            {
                files.removeAtOrdered(index)
            }
        }

        if files.count <= 1
        {
            return false
        }

        var next: String
        switch #complete mode
        {
        case .Once, .Repeat:
            return false

        case .Folder:
            var index = 0_u64
            for i in files.count where files[i] == .currentFile
            {
                index = i
                break
            }

            let nextIndex = (index + 1) % files.count
            if nextIndex == 0
            {
                .folderReadingFiles.clear()
            }

            next = files[nextIndex]

        case .Shuffle:
            next = .pickShuffled(files.toSlice())
        }

        .queueFile(next, remember: false, autoplayScene: autoplayScene)
        return true
    }

    // Picks a file the shuffle has not yet read in this folder, starting a new round
    // once every file has had its turn.
    //
    // The file that has just ended is the one that must not come straight back, so a new round
    // starts with it already taken. The round is not persisted: a shuffle is a walk through a
    // folder, not a property of it.
    mtd pickShuffled(files: const [..] String)->String
    {
        .trackFolderReading(.Shuffle)

        var candidates: Array!{u64}
        for one, index in files where not .folderReadingFiles.contains(one[])
        {
            candidates.add(index)
        }

        if candidates.isEmpty()
        {
            .folderReadingFiles.clear()
            .folderReadingFiles.add(.currentFile)
            for one, index in files where one[] != .currentFile
            {
                candidates.add(index)
            }
        }

        return files[candidates[Random.shared().nextU64(0, candidates.count)]]
    }

    // Answers a viewer that has finished presenting its file with what the play mode calls for.
    //
    // Only the current view has a say: one on its way out reports the end of a file the window
    // has already left. A folder mode brings up the file that follows and tells the viewer to
    // stay as it is; a file alone of its kind in its folder is the whole playlist, so those modes
    // have it presented again.
    mtd continueAfter(view: *Wnd)->Viewer.Continuation
    {
        if view != .currentView
        {
            return .Stop
        }

        switch #complete .playMode
        {
        case .Once:
            return .Stop

        case .Repeat:
            return .Replay

        case .Folder, .Shuffle:
            let autoplay = (view is Viewers.Film.Panel or view is Viewers.Sound.Panel) and
                           (.workspace?.hasSceneTransport() orelse false)
            return .continueFile(.playMode, autoplayScene: autoplay) ? .Next : .Replay
        }
    }

    // Starts the slideshow pace for a view showing content with no end of its own.
    //
    // A progressive viewer may report before the window has committed to it; the commit then
    // starts the count, so the order of the two does not matter.
    mtd showStill(view: *Wnd)
    {
        .stillView = view
        .armSlide()
    }

    // Counts the slideshow pace down for a still picture while a folder mode is on, and stops
    // counting otherwise.
    mtd armSlide()
    {
        .stopSlide()
        if .sceneSlidesPaused or not .stillView or .stillView != .currentView
        {
            return
        }

        if .playMode != .Folder and .playMode != .Shuffle
        {
            return
        }

        .slideTimer = .addTimer(Time.Duration.fromSeconds(.slideSeconds))
    }

    mtd stopSlide()
    {
        if not .slideTimer
        {
            return
        }

        .stopTimer(&.slideTimer)
    }

    // Moves the slideshow on once its pace has elapsed on the picture that started it.
    mtd continueSlide()
    {
        if not .stillView or .stillView != .currentView
        {
            return
        }

        discard .continueFile(.playMode)
    }

    mtd setPlayMode(mode: Viewer.PlayMode, save = true)
    {
        if .playMode == mode
        {
            if save and .sceneSlidesPaused
            {
                .sceneSlidesPaused = false
                .armSlide()
            }

            return
        }

        .resetFolderReading()
        .playMode = mode
        if save
        {
            .sceneSlidesPaused = false
        }

        .trackFolderReading(mode)
        .layoutViewerBar()
        .armSlide()
        if save
        {
            .workspace?.updateMedia()
            catch .saveState()
        }
    }

    mtd setPicturePlaying(playing: bool, restart = false)
    {
        .sceneSlidesPaused = not playing
        if .currentView is Viewers.Picture.Panel as picture where picture.imageView.movie.isAnimated()
        {
            if restart
            {
                picture.imageView.setFrameIndex(0)
            }

            picture.imageView.setPaused(not playing)
        }

        if playing
        {
            if not .slideTimer
            {
                .armSlide()
            }
        }
        else
        {
            .stopSlide()
        }
    }

    mtd setSlideSeconds(seconds: f32)
    {
        .slideSeconds = Math.clamp(seconds, Viewer.SlideMinSeconds, Viewer.SlideMaxSeconds)
        .armSlide()
        catch .saveState()
    }
}
