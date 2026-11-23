#global internal

using Core, Gui, Pixel, Audio

enum SceneTimeMode { Absolute, Relative, Leader }
enum SceneEndMode { Shortest, Independent, LoopLeader }

struct SceneLinks
{
    time:     bool = true
    playback: bool = true
    framing:  bool = true
    scroll:   bool
    mode:     SceneTimeMode
    end:      SceneEndMode = .Independent
    leader:   u64  = Swag.U64.Max
    solo:     u64  = Swag.U64.Max
}

struct ScenePlayer
{
    film:  *Viewers.Film.Panel?
    sound: *Viewers.Sound.Panel?
}

impl ScenePlayer
{
    func from(document: *ViewerWindow?)->ScenePlayer
    {
        switch document?.currentView
        {
        case Viewers.Film.Panel as film:   return {film: film}
        case Viewers.Sound.Panel as sound: return {sound: sound}
        default: return {}
        }
    }

    mtd ready()->bool
    {
        if .film do
            return .film.hasFrame
        return .sound != null and .sound.duration > 0
    }

    mtd seconds()->f64
    {
        if .film do
            return .film.currentSeconds()
        return .sound ? cast(f64, .sound.playbackPosition()) : 0
    }

    mtd duration()->f64
    {
        if .film do
            return .film.video.durationInSeconds()
        return .sound ? cast(f64, .sound.duration) : 0
    }

    mtd rate()->f64
    {
        if .film do
            return .film.playbackRate
        return .sound ? .sound.playbackRate : 1
    }

    mtd isPlaying()->bool => (.film?.playing orelse false) or (.sound?.playing orelse false)

    mtd setPlaying(playing: bool)
    {
        if not .ready() or .isPlaying() == playing do
            return
        if .film do
            .film.togglePlayback()
        else do
            .sound!.togglePlayback()
    }

    mtd stop()
    {
        if .film do
            .film.stopPlayback()
        else do
            .sound?.stopPlayback()
    }

    mtd seek(seconds: f64)
    {
        if .film do
            .film.seekSeconds(seconds)
        else do
            .sound?.seekSeconds(cast(f32, seconds))
    }

    mtd setRate(rate: f64)
    {
        if .film do
            .film.setPlaybackRate(rate)
        else do
            .sound?.setPlaybackRate(rate)
    }

    mtd setSilent(silent: bool)
    {
        if .film do
            .film.setSceneSilent(silent)
        else do
            .sound?.setSceneSilent(silent)
    }
}

impl ViewerWorkspace
{
    mtd isMediaScene()->bool
    {
        let scene = .scene()
        if not scene or scene.views.count < 2 do
            return false
        for view in scene.views where not isMediaFile(.theme(), view.path) do
            return false
        return true
    }

    mtd hasSceneTransport()->bool
    {
        let scene = .scene()
        if not scene or scene.views.count < 2 do
            return false
        for view in scene.views where .isScenePlaybackView(view) do
            return true
        return false
    }

    private mtd isScenePlaybackView(view: const *SceneView)->bool
    {
        if view.document?.currentView is Viewers.Picture.Panel do
            return true
        return isMediaFile(.theme(), view.path) or .theme().fileGlyph(view.path, false).index == cast(s32, ThemeIcons.FileImage)
    }

    mtd usesLinkedTransport(scene: const *ViewerScene)->bool =>
        .usesSharedEnd(scene) or (.comparisonVisible() and scene.linked and scene.links.playback and .isMediaScene())

    private mtd usesSharedEnd(scene: const *ViewerScene)->bool =>
        .isMediaScene() and
        scene.linked and
        scene.links.playback and
        scene.links.end != .Independent

    mtd scenePlayer()->ScenePlayer => ScenePlayer.from(.activeDocument())

    mtd mediaLeader(scene: const *ViewerScene)->u64 =>
        scene.links.mode == .Leader and scene.links.leader < scene.views.count ? scene.links.leader : scene.active

    mtd audibleIndex(scene: const *ViewerScene)->u64
    {
        if scene.links.solo < scene.views.count do
            return scene.links.solo
        if isMediaFile(.theme(), scene.views[scene.active].path) do
            return scene.active
        for view, index in scene.views where isMediaFile(.theme(), view.path) do
            return index
        return scene.active
    }

    mtd updateMediaViewport(document: *ViewerWindow)
    {
        let scene  = .scene()
        let player = ScenePlayer.from(document)
        if not scene do
            return

        let workspace = me
        if player.sound
        {
            player.sound.sceneManaged = .usesSharedEnd(scene)
            let audible = scene.views[.audibleIndex(scene)].document
            player.sound.setSceneSilent(scene.views.count > 1 and document != audible)
            if not .isMediaScene() do
                player.sound.waveform.setSceneAxis(0, 0)

            player.sound.sceneToggle = func|workspace, document|()->bool => workspace.toggleLinkedPlayback(document)
            player.sound.sceneStop = func|workspace|()->bool => workspace.stopLinkedPlayback()
            player.sound.waveform.sceneSeek = func|workspace, document|(seconds)
            {
                let current = workspace.scene()
                if current
                {
                    for view, index in current.views where view.document == document
                    {
                        workspace.seekSceneFrom(seconds, index)
                        return
                    }
                }
            }
        }

        if not player.film do
            return
        for view, index in scene.views where view.document == document
        {
            let area  = document.documentPanel.clientRect()
            let scale = .deviceScale()
            let size  = scene.views.count > 1 and not scene.maximized and scene.layout != .Single ?
                        Math.Point{area.width * scale, area.height * scale} : Math.Point{}
            player.film.sceneManaged = .isMediaScene()
            player.film.sceneOwnsEnd = .usesSharedEnd(scene)
            if player.film.sceneManaged do
                player.film.autoPlayPending = false
            else do
                player.film.clearSceneClock()
            player.film.setSceneViewport(size)
            player.film.setSceneSilent(scene.views.count > 1 and index != .audibleIndex(scene))
            player.film.sceneToggle = func|workspace, document|()->bool => workspace.toggleLinkedPlayback(document)
            player.film.sceneStop   = func|workspace|()->bool => workspace.stopLinkedPlayback()
            player.film.sceneSeek   = func|workspace, document|(seconds) { workspace.linkSceneSeek(document, seconds) }
            return
        }
    }

    mtd createMediaControls()
    {
        let surface = unwrap .surface
        with .mediaPlayPause = CaptionButton.create(surface, .Play, "scope.scene.playPause")
        {
            .sigPressed += func|workspace = me|(_) { workspace.playScene(all: true) }
            .hide()
        }

        with .mediaTransport = CaptionButton.create(surface, .Options, "scope.scene.controlsButton")
        {
            .sigPressed += func|workspace = me|(_) { workspace.showMediaTransport() }
            .hide()
        }

        with .mediaLinks = CaptionButton.create(surface, .Link, "scope.scene.linksButton")
        {
            .sigPressed += func|workspace = me|(_) { workspace.showMediaLinks() }
            .hide()
        }
    }

    mtd createMediaLinkSheet()->*OptionSheet.View
    {
        let workspace = me
        return OptionSheet.View.create(&.mediaLinks.button,
                                       func|workspace|(page) { workspace.describeLinks(page) },
                                       owner: .activeDocument())
    }

    mtd showMediaLinks()
    {
        .createMediaLinkSheet().doModal(&.mediaLinks.button, autoDestroy: true)
    }

    mtd createMediaTransportSheet()->*OptionSheet.View
    {
        return OptionSheet.View.create(&.mediaTransport.button,
                                       func|workspace = me|(page) { workspace.describeTransport(page) },
                                       owner: .activeDocument())
    }

    mtd showMediaTransport()
    {
        .createMediaTransportSheet().doModal(&.mediaTransport.button, autoDestroy: true)
    }

    mtd updateMediaTransport()
    {
        let scene = .scene()
        var canPlay: bool
        if scene and scene.views.count > 1
        {
            for view in scene.views
            {
                if isMediaFile(.theme(), view.path) do
                    canPlay = true
                elif view.document?.currentView is Viewers.Picture.Panel as picture
                {
                    let mode = view.document?.playMode orelse Viewer.PlayMode.Once
                    canPlay = picture.imageView.movie.isAnimated() or mode == .Folder or mode == .Shuffle
                }
                if canPlay do
                    break
            }
        }
        .mediaPlayPause.show(canPlay)
        if not canPlay do
            return
        let playing = .anyMediaPlaying()
        let action  = playing ? appStrings().scene_Pause : appStrings().scene_Play
        let title   = Format.toString("% · %", action, Input.formatKeyShortcut(.Shift, .Space))
        let button  = .mediaPlayPause
        if button.toolTip == title do
            return
        button.toolTip = title
        button.button.setIcon(.theme().icon(playing ? .Pause : .Play, .themeMetrics().wnd_CaptionButtonGlyph))
    }

    mtd updateMedia()
    {
        let media = .isMediaScene()
        let transport = media or .hasSceneTransport()
        .mediaLinks.toolTip = appStrings().scene_Links
        .mediaLinks.show(media)
        .mediaTransport.toolTip = appStrings().scene_Controls
        .mediaTransport.show(.documentCount() > 1)
        .updateMediaTransport()
        if transport and not .mediaTimer do
            .mediaTimer = .addTimer(16'ms)
        elif not transport do
            .stopTimer(&.mediaTimer)
    }

    mtd anyMediaPlaying()->bool
    {
        let scene = .scene()
        if scene
        {
            for view in scene.views where view.document
            {
                let document = view.document
                if ScenePlayer.from(document).isPlaying() or document.sceneAutoPlay or document.slideTimer do
                    return true
                if document.currentView is Viewers.Picture.Panel as picture where picture.imageView.movie.isAnimated() and not picture.imageView.movie.isPaused do
                    return true
            }
        }

        return false
    }

    mtd playScene(all = false)
    {
        let scene = .scene()
        if not scene do
            return
        if all or scene.linked and scene.links.playback
        {
            .setScenePlaying(not .anyMediaPlaying())
        }
        else
        {
            let selected = .scenePlayer()
            selected.setPlaying(not selected.isPlaying())
        }
    }

    mtd setScenePlaying(playing: bool)
    {
        let scene = unwrap .scene()
        scene.playbackWasRunning = playing
        for view in scene.views where view.document and .isScenePlaybackView(view)
        {
            let document = view.document
            if not isMediaFile(.theme(), view.path)
            {
                document.setPicturePlaying(playing)
                continue
            }
            let player   = ScenePlayer.from(document)
            if not player.film and not player.sound and document.currentView and document.pendingFile.isEmpty() and not document.outgoingView do
                continue
            let pending  = not player.ready() or not document.pendingFile.isEmpty() or document.outgoingView != null
            document.sceneAutoPlay = playing and pending
            if not playing or not pending do
                player.setPlaying(playing)
        }
        .updateMediaTransport()
    }

    mtd stopScene()
    {
        let scene = unwrap .scene()
        scene.playbackWasRunning = false
        for view in scene.views where view.document and .isScenePlaybackView(view)
        {
            view.document.sceneAutoPlay = false
            if not isMediaFile(.theme(), view.path)
            {
                view.document.setPicturePlaying(false, restart: true)
                continue
            }
            ScenePlayer.from(view.document).stop()
        }
        .updateMediaTransport()
    }

    mtd scenePlayModeIs(mode: Viewer.PlayMode)->bool
    {
        let scene = unwrap .scene()
        if scene.links.end != .Independent do
            return false
        for view in scene.views where .isScenePlaybackView(view)
        {
            let current = view.document ? view.document.playMode : view.playMode
            if current != mode do
                return false
        }
        return true
    }

    mtd setScenePlayMode(mode: Viewer.PlayMode)
    {
        let scene = unwrap .scene()
        scene.links.end = .Independent
        for &view in scene.views where .isScenePlaybackView(view)
        {
            view.playMode = mode
            view.document?.setPlayMode(mode, save: false)
        }
        .synchronizeMedia()
        catch .primary.saveState()
    }

    private mtd toggleLinkedPlayback(document: *ViewerWindow)->bool
    {
        let scene = .scene()
        if not scene or not .usesLinkedTransport(scene) do
            return false
        for view in scene.views where view.document == document
        {
            .playScene()
            return true
        }

        return false
    }

    private mtd stopLinkedPlayback()->bool
    {
        let scene = .scene()
        if not scene or not .usesLinkedTransport(scene) do
            return false
        .stopScene()
        return true
    }

    mtd describeTransport(page: *OptionSheet.Page)
    {
        let text = appStrings()
        let workspace = me
        let size = themeRowIconSize(.themeMetrics())
        let scene = unwrap .scene()
        page.addLink(text.scene_Layout, sceneLayoutTitle(scene.visibleLayout()),
                     func|workspace|(layouts)
                     {
                         let current = unwrap workspace.scene()
                         for layout in SceneCommands.LayoutValues where current.supportsLayout(layout) do
                             layouts.addChoice(sceneLayoutTitle(layout), current.visibleLayout() == layout,
                                               func|workspace, layout|() { workspace.setLayout(layout) })
                     },
                     icon: .theme().icon(.SelectAll, size))
        page.addAction(scene.maximized ? text.scene_RestoreLayout : text.scene_Maximize,
                       func|workspace|() { workspace.toggleMaximized() },
                       icon: .theme().icon(scene.maximized ? .ExitFullScreen : .FullScreen, size))
        if not .isMediaScene() do
            page.addLink(text.scene_ViewLinks, "",
                         func|workspace|(links) { workspace.describeLinks(links) },
                         icon: .theme().icon(.Link, size))
        if not .hasSceneTransport() do
            return

        page.addHeading(text.scene_Transport)
        page.addAction(text.scene_Play, func|workspace|() { workspace.setScenePlaying(true) }, icon: .theme().icon(.Play, size))
        page.addAction(text.scene_Pause, func|workspace|() { workspace.setScenePlaying(false) }, icon: .theme().icon(.Pause, size))
        page.addAction(text.scene_Stop, func|workspace|() { workspace.stopScene() }, icon: .theme().icon(.Stop, size))
        page.addHeading(text.scene_PlayModeAll)
        for mode in Viewer.PlayModeValues do
            page.addChoice(Viewer.playModeText(mode),
                           .scenePlayModeIs(mode),
                           func|workspace, mode|() { workspace.setScenePlayMode(mode) },
                           icon: .theme().icon(Viewer.playModeIcon(mode), size))
    }

    mtd isOpenInAnotherView(document: *ViewerWindow, path: string)->bool
    {
        let scene = .scene()
        if scene
        {
            for view in scene.views where view.document != document
            {
                if view.path == path or (view.document and view.document.pendingFile == path) do
                    return true
            }
        }

        return false
    }

    private mtd linkSceneSeek(document: *ViewerWindow, seconds: f64)
    {
        let scene = .scene()
        if not scene or not .isMediaScene() or not scene.linked or not scene.links.time do
            return
        for view, index in scene.views where view.document == document
        {
            .seekLinkedViews(scene, seconds, index)
            return
        }
    }

    mtd seekScene(seconds: f64)
    {
        let scene = .scene()
        if not scene do
            return
        .seekSceneFrom(seconds, scene.active)
    }

    mtd seekSceneFrom(seconds: f64, source: u64)
    {
        let scene  = unwrap .scene()
        let player = ScenePlayer.from(scene.views[source].document)
        if not player.isPlaying() do
            scene.playbackWasRunning = false
        player.seek(seconds)
        .seekLinkedViews(scene, seconds, source)
    }

    private mtd seekLinkedViews(scene: const *ViewerScene, seconds: f64, source: u64)
    {
        if not scene.linked or not scene.links.time do
            return
        let relative = scene.links.mode == .Relative
        let origin   = relative ? scene.views[source].offset : 0
        for view, index in scene.views where index != source
        {
            let target = seconds + (relative ? view.offset : 0) - origin
            ScenePlayer.from(view.document).seek(target)
        }
    }

    mtd alignSceneHere()
    {
        let scene = .scene()
        if not scene or not .isMediaScene() do
            return
        let origin = .scenePlayer().seconds()
        for &view in scene.views do
            view.offset = ScenePlayer.from(view.document).seconds() - origin
        scene.links.mode = .Relative
        scene.linked     = true
        scene.links.time = true
        .invalidate()
        catch .primary.saveState()
    }

    private mtd refreshSoundAxes(scene: *ViewerScene, relative: bool)
    {
        let shared = scene.layout == .Stacked and scene.linked and scene.links.time
        var beginning, end: f64
        if shared
        {
            for &view in scene.views
            {
                let sound = ScenePlayer.from(view.document).sound
                if sound
                {
                    let offset = relative ? view.offset : 0
                    beginning = Math.min(beginning, -offset)
                    end       = Math.max(end, sound.duration - offset)
                }
            }
        }

        for &view in scene.views
        {
            let sound = ScenePlayer.from(view.document).sound
            if sound do
                sound.waveform.setSceneAxis(cast(f32, beginning + (relative ? view.offset : 0)), cast(f32, end - beginning))
        }
    }

    mtd synchronizeMedia()
    {
        let scene = .scene()
        if not scene do
            return

        // Group requests can arrive before a cell has finished opening or changing files.
        for view in scene.views where view.document and view.document.sceneAutoPlay
        {
            let document = view.document
            let player   = ScenePlayer.from(document)
            if document.pendingFile.isEmpty() and not document.outgoingView and player.ready()
            {
                document.sceneAutoPlay = false
                player.setPlaying(true)
            }
        }

        if not .isMediaScene() do
            return

        let audible     = .audibleIndex(scene)
        let leaderIndex = .mediaLeader(scene)
        let leader      = ScenePlayer.from(scene.views[leaderIndex].document)
        let sharedEnd   = .usesSharedEnd(scene)
        for view, index in scene.views
        {
            let player = ScenePlayer.from(view.document)
            player.setSilent(index != audible)
            if player.sound do
                player.sound.sceneManaged = sharedEnd
            if player.film do
                player.film.sceneOwnsEnd = sharedEnd
        }

        leader.film?.clearSceneClock()
        leader.film?.updatePlayback()
        let relative = scene.links.mode == .Relative
        .refreshSoundAxes(scene, relative)
        let origin     = relative ? scene.views[leaderIndex].offset : 0
        let clock      = leader.seconds() - origin
        let play       = leader.isPlaying()
        let wasPlaying = scene.playbackWasRunning
        let linkedPlayback = scene.linked and scene.links.playback
        defer
        {
            scene!.playbackWasRunning = linkedPlayback and leader.isPlaying()
        }
        let rate        = leader.rate()
        let leaderEnded = leader.duration() > 0 and leader.seconds() >= leader.duration()
        var shortest    = leader.duration() - origin
        var statusChanged: bool
        defer
        {
            if statusChanged do
                .invalidate()
        }

        for &view, index in scene.views
        {
            let wasBehind = view.behind
            defer statusChanged = statusChanged or view.behind != wasBehind
            if index == leaderIndex
            {
                view.behind = false
                continue
            }

            let player = ScenePlayer.from(view.document)
            if not player.ready()
            {
                player.film?.updatePlayback()
                continue
            }

            let offset = relative ? view.offset : 0
            shortest = Math.min(shortest, player.duration() - offset)

            // Independent endings let a cell keep its own clock when another file ends or changes.
            if not sharedEnd
            {
                if scene.linked and scene.links.playback and play and player.isPlaying() do
                    player.setRate(rate)
                player.film?.clearSceneClock()
                player.film?.updatePlayback()
                view.behind = false
                continue
            }

            if scene.links.playback
            {
                player.setRate(rate)
                player.setPlaying(play and clock + offset < player.duration())
            }

            if not scene.links.time
            {
                player.film?.clearSceneClock()
                player.film?.updatePlayback()
                view.behind = false
                continue
            }

            let target = Math.clamp(clock + offset, 0, player.duration())
            if player.film
            {
                player.film.followSceneClock(target)
                player.film.updatePlayback()
                let frame = player.film.video.frameAtTime(target)
                let count = player.film.video.frameCount()
                view.behind = player.film.frameIndex < (count ? Math.min(frame, count - 1) : frame)
            }
            elif Math.abs(player.seconds() - target) > 0.035
            {
                player.sound?.seekSeconds(cast(f32, target), remember: false)
            }
        }

        if not sharedEnd do
            return
        if scene.links.end == .Shortest and shortest > 0 and clock >= shortest
        {
            for view in scene.views do
                ScenePlayer.from(view.document).setPlaying(false)
        }
        elif scene.links.end == .LoopLeader and leaderEnded and (play or wasPlaying)
        {
            .seekSceneFrom(0, leaderIndex)
            for view in scene.views do
                ScenePlayer.from(view.document).setPlaying(true)
        }
    }

    mtd describeLinks(page: *OptionSheet.Page)
    {
        let scene = .scene()
        if not scene do
            return
        let text      = appStrings()
        let workspace = me
        let media     = .isMediaScene()
        page.addToggle(text.scene_Linked, scene.linked, func|workspace|(value) { workspace.setSceneLink(MediaCommands.Linked, value) })
        if media
        {
            page.addToggle(text.scene_LinkTime, scene.links.time, func|workspace|(value) { workspace.setSceneLink(MediaCommands.Time, value) })
            page.addToggle(text.scene_LinkPlayback, scene.links.playback, func|workspace|(value) { workspace.setSceneLink(MediaCommands.Playback, value) })
        }
        page.addToggle(text.scene_LinkFraming, scene.links.framing, func|workspace|(value) { workspace.setSceneLink(MediaCommands.Framing, value) })
        page.addToggle(text.scene_LinkScroll, scene.links.scroll, func|workspace|(value) { workspace.setSceneLink(MediaCommands.Scroll, value) })
        if not media do
            return
        page.addHeading(text.scene_LinkTime)
        page.addSegments(text.scene_LinkTime,
                         [text.scene_Absolute, text.scene_Relative, text.scene_Leader],
                         cast(u32, scene.links.mode),
                         func|workspace|(index) { workspace.setTimeMode(MediaCommands.TimeValues[index]) })

        page.addAction(text.scene_AlignHere, func|workspace|() { workspace.alignSceneHere() })
        page.addAction(text.scene_AlignSound, func|workspace|() { workspace.alignSceneSound() })
        page.addHeading(text.scene_AtEnd)
        for mode in [SceneEndMode.Independent, .Shortest, .LoopLeader] do
            page.addChoice(sceneEndTitle(mode),
                           mode == scene.links.end,
                           func|workspace, mode|() { workspace.setEndMode(mode) },
                           icon: .theme().icon(sceneEndIcon(mode), themeRowIconSize(.themeMetrics())))
        page.addAction(text.scene_Solo, func|workspace|() { workspace.toggleSolo() })
    }
}
