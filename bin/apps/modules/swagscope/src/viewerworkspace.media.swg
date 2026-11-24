#global internal

using Core, Gui, Pixel, Audio

enum SceneTimeMode { Absolute, Relative, Leader }
enum SceneEndMode { Shortest, Independent, LoopLeader }

enum ScenePlaybackKind { None, Film, Sound, Picture }

private func isTimedMedia(kind: ScenePlaybackKind)->bool => kind == .Film or kind == .Sound

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
        return .allMedia(scene)
    }

    mtd allMedia(scene: const *ViewerScene)->bool
    {
        for view in scene.views where not isTimedMedia(.scenePlaybackKind(view)) do
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

    private mtd isScenePlaybackView(view: const *SceneView)->bool => .scenePlaybackKind(view) != .None

    private mtd scenePlaybackKind(view: const *SceneView)->ScenePlaybackKind
    {
        let document = view.document
        if document and document.pendingFile.isEmpty() and (document.isExploring() or document.home.isLocallyVisible()) do
            return .None
        if document and document.currentView and document.pendingFile.isEmpty() and not document.outgoingView
        {
            switch document.currentView
            {
            case Viewers.Film.Panel:    return .Film
            case Viewers.Sound.Panel:   return .Sound
            case Viewers.Picture.Panel: return .Picture
            default: return .None
            }
        }

        if view.readState and not document and not view.reading.viewer.isEmpty() do
            return playbackKindForPlugin(view.reading.viewer)
        let name: string = document and not document.pendingFile.isEmpty() ? document.pendingFile : view.path
        var index: u64
        if .primary.index.namePlugin(name, &index) do
            return playbackKindForPlugin(.primary.index.plugins[index].key)
        return .None
    }

    private func playbackKindForPlugin(key: string)->ScenePlaybackKind
    {
        switch key
        {
        case "video": return .Film
        case "sound": return .Sound
        case "image": return .Picture
        default:      return .None
        }
    }

    mtd usesLinkedTransport(scene: const *ViewerScene)->bool =>
        .usesSharedEnd(scene) or (.comparisonVisible() and scene.linked and scene.links.playback and .isMediaScene())

    private mtd usesSharedEnd(scene: const *ViewerScene)->bool =>
        .isMediaScene() and
        .effectiveEndMode(scene) != .Independent

    mtd effectiveEndMode(scene: const *ViewerScene)->SceneEndMode =>
        scene.linked and scene.links.playback ? scene.links.end : .Independent

    mtd scenePlayer()->ScenePlayer => ScenePlayer.from(.activeDocument())

    mtd mediaLeader(scene: const *ViewerScene)->u64 =>
        scene.links.mode == .Leader and scene.links.leader < scene.views.count ? scene.links.leader : scene.active

    mtd audibleIndex(scene: const *ViewerScene)->u64
    {
        if scene.links.solo < scene.views.count do
            return scene.links.solo
        if isTimedMedia(.scenePlaybackKind(&scene.views[scene.active])) do
            return scene.active
        for view, index in scene.views where isTimedMedia(.scenePlaybackKind(view)) do
            return index
        return scene.active
    }

    mtd updateMediaViewport(document: *ViewerWindow)
    {
        let scene  = .scene()
        let player = ScenePlayer.from(document)
        if not scene do
            return

        defer .resumeQueuedPlayback(document)
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
            player.sound.sceneSeek = func|workspace, document|(seconds) { workspace.linkSceneSeek(document, seconds) }
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
            if scene.views.count > 1 do
                player.film.autoPlayPending = false
            if not player.film.sceneManaged do
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

        with .mediaTransport = CaptionButton.create(surface, .Grid, "scope.scene.controlsButton")
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
        let anchor = .isMediaScene() ? .mediaLinks : .mediaTransport
        return OptionSheet.View.create(&anchor.button,
                                       func|workspace|(page) { workspace.describeLinks(page) },
                                       owner: .activeDocument())
    }

    mtd showMediaLinks()
    {
        let anchor = .isMediaScene() ? .mediaLinks : .mediaTransport
        .createMediaLinkSheet().doModal(&anchor.button, autoDestroy: true)
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

    mtd canPlayScene()->bool
    {
        let scene = .scene()
        if not scene or scene.views.count < 2 do
            return false
        for view in scene.views where .canPlayView(view) do
            return true
        return false
    }

    private mtd canPlayView(view: const *SceneView)->bool
    {
        let kind = .scenePlaybackKind(view)
        if isTimedMedia(kind) do
            return true
        if view.document?.currentView is Viewers.Picture.Panel as picture where kind == .Picture
        {
            let mode = view.document!.playMode
            return picture.imageView.movie.isAnimated() or mode == .Folder or mode == .Shuffle
        }
        return false
    }

    mtd updateMediaTransport()
    {
        let canPlay = .canPlayScene()
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
        let transport = .canPlayScene()
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
            for view in scene.views where view.document and viewIsPlaying(view.document) do
                return true
        }
        return false
    }

    private func viewIsPlaying(document: *ViewerWindow)->bool
    {
        if ScenePlayer.from(document).isPlaying() or document.sceneAutoPlay or document.slideTimer do
            return true
        if document.currentView is Viewers.Picture.Panel as picture do
            return picture.imageView.movie.isAnimated() and not picture.imageView.movie.isPaused
        return false
    }

    mtd canRunTransport(id: WndId)->bool
    {
        let scene = .scene()
        if not scene do
            return false
        for view in scene.views where view.document and .canPlayView(view)
        {
            let playing = viewIsPlaying(view.document)
            if id == MediaCommands.Play ? not playing : playing do
                return true
            if id != MediaCommands.Stop do
                continue
            if ScenePlayer.from(view.document).seconds() > 0 do
                return true
            if view.document.currentView is Viewers.Picture.Panel as picture where picture.imageView.movie.frameIndex > 0 do
                return true
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
            if .scenePlaybackKind(view) == .Picture
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
            if .scenePlaybackKind(view) == .Picture
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
        if .effectiveEndMode(scene) != .Independent do
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
        .updateMedia()
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
                                               func|workspace, layout|() { workspace.setLayout(layout) },
                                               disabled: workspace.focusOnGrid and layout == .Single,
                                               icon: workspace.theme().icon(sceneLayoutIcon(layout), themeRowIconSize(workspace.themeMetrics())))
                     },
                     icon: .theme().icon(sceneLayoutIcon(scene.visibleLayout()), size))
        page.addAction(scene.maximized ? text.scene_RestoreLayout : text.scene_Maximize,
                       func|workspace|() { workspace.toggleMaximized() }, disabled: .focusOnGrid,
                       icon: .theme().icon(scene.maximized ? .ExitFullScreen : .FullScreen, size))
        if not .isMediaScene() and .hasViewLinks() do
            page.addLink(text.scene_ViewLinks, "",
                         func|workspace|(links) { workspace.describeLinks(links) },
                         icon: .theme().icon(.Link, size))
        if not .hasSceneTransport() do
            return

        if .canPlayScene()
        {
            page.addHeading(text.scene_Transport)
            for id in [MediaCommands.Play, MediaCommands.Pause, MediaCommands.Stop] do
                page.addCommand(id, .activeDocument())
        }
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
            if not ScenePlayer.from(document).isPlaying() do
                scene.playbackWasRunning = false
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
        if not scene.linked or not scene.links.time or not .isMediaScene() do
            return
        let relative = scene.links.mode == .Relative
        let origin   = relative ? scene.views[source].offset : 0
        for view, index in scene.views where index != source
        {
            let target = seconds + (relative ? view.offset : 0) - origin
            ScenePlayer.from(view.document).seek(target)
        }
    }

    mtd mediaCaption(document: *ViewerWindow, name: string)->String
    {
        let scene = .scene()
        var label = String.from(name)
        if scene and scene.linked and .isMediaScene()
        {
            for view in scene.views where view.document == document
            {
                if scene.links.mode == .Relative and view.offset != 0 do
                    label += Format.toString(" · %{+f2} s", view.offset)
                if view.behind do
                    label += Format.toString(" · %", appStrings().scene_Behind)
                break
            }
        }
        return label
    }

    mtd refreshMediaCaptions()
    {
        let scene = .scene()
        if scene
        {
            if .comparisonVisible() do
                .comparison!.refresh()
            else
            {
                for view in scene.views where view.document do
                    view.document.layoutCellCaption()
            }
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
        .refreshMediaCaptions()
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

    // A queued group play follows the file even if its view has since become the only one.
    private mtd resumeQueuedPlayback(document: *ViewerWindow)
    {
        if not document.sceneAutoPlay or not document.pendingFile.isEmpty() or document.outgoingView do
            return
        let player = ScenePlayer.from(document)
        if player.ready()
        {
            document.sceneAutoPlay = false
            player.setPlaying(true)
        }
    }

    mtd synchronizeMedia()
    {
        let scene = .scene()
        if not scene do
            return

        for view in scene.views where view.document do
            .resumeQueuedPlayback(view.document)

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
                .refreshMediaCaptions()
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
        let size      = themeRowIconSize(.themeMetrics())
        page.addToggle(text.scene_Linked, scene.linked, func|workspace|(value) { workspace.setSceneLink(MediaCommands.Linked, value) })
        if media
        {
            page.addToggle(text.scene_LinkTime, scene.links.time, func|workspace|(value) { workspace.setSceneLink(MediaCommands.Time, value) })
            page.addToggle(text.scene_LinkPlayback, scene.links.playback, func|workspace|(value) { workspace.setSceneLink(MediaCommands.Playback, value) })
        }
        if .canLinkFraming() do
            page.addToggle(text.scene_LinkFraming, scene.links.framing, func|workspace|(value) { workspace.setSceneLink(MediaCommands.Framing, value) })
        if .canLinkScroll() do
            page.addToggle(text.scene_LinkScroll, scene.links.scroll, func|workspace|(value) { workspace.setSceneLink(MediaCommands.Scroll, value) })
        if not media do
            return
        page.addHeading(text.scene_LinkTime)
        if .focusOnGrid
        {
            for mode in MediaCommands.TimeValues do
                page.addChoice(sceneTimeTitle(mode), scene.links.mode == mode,
                               func|workspace, mode|() { workspace.setTimeMode(mode) }, disabled: mode == .Leader)
        }
        else
        {
            page.addSegments(text.scene_LinkTime,
                             [text.scene_Absolute, text.scene_Relative, text.scene_Leader],
                             cast(u32, scene.links.mode),
                             func|workspace|(index) { workspace.setTimeMode(MediaCommands.TimeValues[index]) })
        }

        page.addAction(text.scene_AlignHere, func|workspace|() { workspace.alignSceneHere() }, disabled: .focusOnGrid, icon: .theme().icon(.GoTo, size))
        page.addAction(text.scene_AlignSound, func|workspace|() { workspace.alignSceneSound() }, icon: .theme().icon(.AudioTracks, size))
        page.addHeading(text.scene_AtEnd)
        for mode in [SceneEndMode.Independent, .Shortest, .LoopLeader] do
            page.addChoice(sceneEndTitle(mode),
                           mode == .effectiveEndMode(scene),
                           func|workspace, mode|() { workspace.setEndMode(mode) },
                           icon: .theme().icon(sceneEndIcon(mode), themeRowIconSize(.themeMetrics())))
        page.addToggle(text.scene_Solo, scene.links.solo == scene.active, func|workspace|(_) { workspace.toggleSolo() }, disabled: .focusOnGrid)
    }
}
