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
    end:      SceneEndMode
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

    mtd setMute(muted: bool)
    {
        if .film do
            .film.setMuted(muted)
        else do
            .sound?.setMuted(muted)
    }

    mtd setVolume(value: f32)
    {
        if .film do
            .film.setVolume(value)
        else do
            .sound?.setVolume(value)
    }
}

struct SceneTransport
{
    using wnd:       Wnd
    late workspace:  *ViewerWorkspace
    late veil:       *Viewers.Film.BottomVeil
    late linkButton: *IconButton
    timer:           *Timer?
    lastPointerAt:   u64
    busy:            bool
    lastDuration:    f64 = -1
}

impl SceneTransport
{
    func create(workspace: *ViewerWorkspace)->*SceneTransport
    {
        let result = Wnd.create'SceneTransport(workspace, "scope.scene.transport")
        result.workspace       = workspace
        result.lastPointerAt   = Time.monotonicMicroseconds()
        result.backgroundStyle = .Transparent
        result.veil            = Viewers.Film.BottomVeil.create(result)
        result.veil.dockStyle  = .Center
        result.linkButton      = IconButton.createQuiet(result.veil, "scope.scene.links")
        result.linkButton.setQuietText(appStrings().scene_Linked)
        result.linkButton.sigPressed += func|transport = result|(button)
        {
            transport.openLinks(button)
        }

        result.veil.playButton.sigPressed += func|transport = result|(_)
        {
            transport.workspace.playScene()
        }

        result.veil.timeline.sigEndChange += func|transport = result|(timeline)
        {
            transport.workspace.seekScene(timeline.value())
        }

        result.veil.optionsButton.sigPressed += func|transport = result|(button)
        {
            let player = transport.workspace.scenePlayer()
            player.film?.showOptions(button)
        }

        result.veil.timeButton.sigPressed += func|transport = result|(_)
        {
            let player = transport.workspace.scenePlayer()
            if player.film do
                player.film.promptGoToTime()
            else do
                player.sound?.promptGoToTime()
        }

        result.veil.tracksButton.sigPressed += func|transport = result|(button)
        {
            let player = transport.workspace.scenePlayer()
            player.film?.showTracks(button)
        }

        result.veil.muteButton.sigCheckedChanged += func|transport = result|(button)
        {
            if not transport.busy do
                transport.workspace.audiblePlayer().setMute(button.isChecked)
        }

        result.veil.volumeSlider.sigChanged += func|transport = result|(slider)
        {
            if not transport.busy do
                transport.workspace.audiblePlayer().setVolume(slider.value())
        }

        result.veil.hide()
        result.timer = result.addTimer(16'ms)
        return result
    }

    mtd createLinkSheet(button: *IconButton)->*OptionSheet.View
    {
        let workspace = .workspace
        let sheet     = OptionSheet.View.create(button,
                                                func|workspace|(page) { workspace.describeLinks(page) },
                                                owner: workspace.activeDocument())
        sheet.wndFlags.add(.TopMost)
        return sheet
    }

    mtd openLinks(button: *IconButton)
    {
        .createLinkSheet(button).doModal(button, autoDestroy: true)
    }

    mtd refresh()
    {
        let workspace = .workspace
        if not workspace.isMediaScene()
        {
            .veil.hide()
            .stopTimer(&.timer)
            workspace.concealMediaCaption(false)
            return
        }

        if not .timer do
            .timer = .addTimer(16'ms)
        let player   = workspace.scenePlayer()
        let duration = player.duration()
        let chrome   = workspace.mediaChromeVisible()
        workspace.concealMediaCaption(not chrome)
        .veil.show(chrome and not workspace.switcher)
        if not .veil.isLocallyVisible() do
            return

        let area   = workspace.clientRect()
        let bottom = workspace.comparisonVisible() ? SceneComparison.FooterHeight : 0
        .setPosition({area.x, area.bottom() - Viewers.Film.BottomHeight - bottom, area.width, Viewers.Film.BottomHeight})
        .bringToFront()
        if duration != .lastDuration
        {
            .lastDuration = duration
            .veil.timeline.setBounds(0, cast(f32, duration), 0.01)
        }

        .veil.timeline.enable(player.ready())
        .veil.playButton.enable(player.ready())
        .veil.optionsButton.enable(player.film != null)
        .veil.tracksButton.enable(player.film != null)
        .veil.timeButton.enable(player.ready())
        .veil.timeButton.setTextColor(Color.fromArgb(Argb.White))
        .veil.timeline.setValueWithoutGesture(cast(f32, player.seconds()))
        .veil.setTime(Viewer.timeText(player.seconds()), Viewer.durationText(duration))
        let play = player.isPlaying()
        .veil.playButton.setIcon(.theme().icon(play ? .Pause : .Play, themeActionIconSize(.themeMetrics())))
        .veil.playButton.toolTip = play ? appStrings().scene_Pause : appStrings().scene_Play
        .linkButton.setQuietText(appStrings().scene_Linked)
        .linkButton.setTextColor(workspace.scene()!.linked ? .themeColors().arc : .themeColors().softText)
        let options = .veil.optionsButton.position
        .linkButton.setPosition({options.x - 108, options.y, 100, options.height}, computeLayout: false)
        let audible = workspace.audiblePlayer()
        let muted   = audible.film?.muted orelse (audible.sound?.muted orelse false)
        let volume  = audible.film?.volume orelse (audible.sound?.volume orelse 1)
        .busy = true
        .veil.muteButton.setChecked(muted)
        .veil.volumeSlider.enable(not muted)
        .veil.volumeSlider.setValueWithoutGesture(volume)
        .busy = false
    }
}

impl IWnd for SceneTransport
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        if not .veil.isLocallyVisible() do
            return
        let area  = .clientRect()
        let ink   = Color.fromArgb(Argb.Black)
        let shade = Brush.createLinearGradient(0, area.y, 0, area.bottom(), ink.withAlphaF32(0), ink.withAlphaF32(0.86))
        evt.paintContext.painter.fillRect(area, shade)
    }

    mtd impl onTimerEvent(_: *TimerEvent)
    {
        .workspace.synchronizeMedia()
        .refresh()
        if .workspace.comparisonVisible() do
            .workspace.comparison!.invalidate()
    }
}

impl ViewerWorkspace
{
    mtd isMediaScene()->bool
    {
        let scene = .scene()
        if not scene or scene.views.count < 2 do
            return false
        for view in scene.views
        {
            let kind = .theme().fileGlyph(view.path, false).index
            if kind != cast(s32, ThemeIcons.FileVideo) and kind != cast(s32, ThemeIcons.FileAudio) do
                return false
        }

        return true
    }

    mtd mediaChromeVisible()->bool
    {
        let scene = .scene()
        if not scene or not .isMediaScene() do
            return false
        return .switcher or
               not .scenePlayer().isPlaying() or
               not .transport or
               Time.monotonicMicroseconds() - .transport.lastPointerAt < 2_200_000 or
               .transport.veil.timeline.dragging or
               .app().isInModalLoop()
    }

    mtd concealMediaCaption(concealed: bool)
    {
        if .compactMedia == concealed do
            return
        .compactMedia = concealed
        .surface?.wnd.setCaptionConcealed(concealed)
        .tabs.layoutTabs()
        .overlay.invalidate()
    }

    mtd scenePlayer()->ScenePlayer => ScenePlayer.from(.activeDocument())

    mtd mediaLeader(scene: const *ViewerScene)->u64 =>
        scene.links.mode == .Leader and scene.links.leader < scene.views.count ? scene.links.leader : scene.active

    mtd audibleIndex(scene: const *ViewerScene)->u64 =>
        scene.links.solo < scene.views.count ? scene.links.solo : scene.active

    mtd audiblePlayer()->ScenePlayer
    {
        let scene = .scene()
        return scene ? ScenePlayer.from(scene.views[.audibleIndex(scene)].document) : ScenePlayer{}
    }

    mtd updateMediaViewport(document: *ViewerWindow)
    {
        let scene  = .scene()
        let player = ScenePlayer.from(document)
        if not scene do
            return
        if player.sound
        {
            player.sound.sceneManaged = .isMediaScene()
            if not player.sound.sceneManaged
            {
                player.sound.waveform.setSceneAxis(0, 0)
                player.sound.setSceneSilent(false)
            }
        }

        if player.sound and not player.sound.waveform.sceneSeek
        {
            let workspace = me
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
            let rect  = .viewRect(scene, index)
            let scale = .deviceScale()
            let size  = scene.views.count > 1 and not scene.maximized and scene.layout != .Single ?
                        Math.Point{rect.width * scale, rect.height * scale} : Math.Point{}
            player.film.sceneManaged = .isMediaScene()
            if player.film.sceneManaged do
                player.film.autoPlayPending = false
            else do
                player.film.clearSceneClock()
            player.film.setSceneViewport(size)
            player.film.setSceneSilent(scene.views.count > 1 and index != .audibleIndex(scene))
            return
        }
    }

    mtd updateMedia()
    {
        if .isMediaScene() and not .transport do
            .transport = SceneTransport.create(me)
        .transport?.refresh()
    }

    mtd noteMediaPointer()
    {
        if not .transport or not .isMediaScene() do
            return
        .transport.lastPointerAt = Time.monotonicMicroseconds()
        .concealMediaCaption(false)
    }

    mtd paintMediaCaption(painter: *Painter, rect: Math.Rectangle, view: const *SceneView, text: string, active: bool)
    {
        let colors = .themeColors()
        let font   = .theme().createDefaultFont(12)
        let radius = .themeMetrics().corner_Chip
        let scene  = unwrap .scene()
        let offset = scene.linked and scene.links.mode == .Relative ?
                     Format.toString(" · %{+f2} s", view.offset) : String{}
        var title = String.from(text)
        title += offset
        let width = Math.min(Painter.measureString(title, font).width + 18, rect.width - 24)
        let chip  = Math.Rectangle{rect.x + 12, Math.max(rect.y, .stripInset()) + 12, width, 25}
        painter.fillRoundRect(chip, radius, radius, colors.raised)
        painter.drawStringCenter(chip.horzCenter(), chip.vertCenter(), Painter.elideString(title, font, width - 12, .deviceScale()), font, colors.text)
        if active do
            painter.drawRect({rect.x + 1, rect.y + 1, rect.width - 2, rect.height - 2}, colors.arc, 2)
        if view.behind do
            painter.drawString(chip.x, chip.bottom() + 5, appStrings().scene_Behind, font, colors.caution)
    }

    mtd playScene()
    {
        let scene = .scene()
        if not scene do
            return
        let selected = .scenePlayer()
        let player   = ScenePlayer.from(scene.views[.mediaLeader(scene)].document)
        let play     = not (scene.linked and scene.links.playback ? player.isPlaying() : selected.isPlaying())
        if scene.linked and scene.links.playback
        {
            for view in scene.views do
                ScenePlayer.from(view.document).setPlaying(play)
        }
        else
        {
            selected.setPlaying(play)
        }

        .transport?.refresh()
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
        let scene = unwrap .scene()
        ScenePlayer.from(scene.views[source].document).seek(seconds)
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
        .overlay.invalidate()
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
        if not scene or not .isMediaScene() do
            return

        let audible     = .audibleIndex(scene)
        let leaderIndex = .mediaLeader(scene)
        let leader      = ScenePlayer.from(scene.views[leaderIndex].document)
        leader.film?.clearSceneClock()
        leader.setSilent(leaderIndex != audible)
        leader.film?.updatePlayback()
        let relative = scene.links.mode == .Relative
        .refreshSoundAxes(scene, relative)
        let origin      = relative ? scene.views[leaderIndex].offset : 0
        let clock       = leader.seconds() - origin
        let play        = leader.isPlaying()
        let rate        = leader.rate()
        let leaderEnded = leader.duration() > 0 and leader.seconds() >= leader.duration()
        let independent = scene.links.end == .Independent and leaderEnded
        var shortest    = leader.duration() - origin
        var statusChanged: bool
        defer
        {
            if statusChanged and .mediaChromeVisible() do
                .overlay.invalidate()
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
            player.setSilent(index != audible)
            if not player.ready()
            {
                player.film?.updatePlayback()
                continue
            }

            let offset = relative ? view.offset : 0
            shortest = Math.min(shortest, player.duration() - offset)
            if not scene.linked or independent
            {
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

        if not scene.linked or not scene.links.playback do
            return
        if scene.links.end == .Shortest and shortest > 0 and clock >= shortest
        {
            for view in scene.views do
                ScenePlayer.from(view.document).setPlaying(false)
        }
        elif scene.links.end == .LoopLeader and leaderEnded
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
        page.addToggle(text.scene_Linked, scene.linked, func|workspace|(value) { workspace.setSceneLink(MediaCommands.Linked, value) })
        page.addToggle(text.scene_LinkTime, scene.links.time, func|workspace|(value) { workspace.setSceneLink(MediaCommands.Time, value) })
        page.addToggle(text.scene_LinkPlayback, scene.links.playback, func|workspace|(value) { workspace.setSceneLink(MediaCommands.Playback, value) })
        page.addToggle(text.scene_LinkFraming, scene.links.framing, func|workspace|(value) { workspace.setSceneLink(MediaCommands.Framing, value) })
        page.addToggle(text.scene_LinkScroll, scene.links.scroll, func|workspace|(value) { workspace.setSceneLink(MediaCommands.Scroll, value) })
        page.addHeading(text.scene_LinkTime)
        page.addSegments(text.scene_LinkTime,
                         [text.scene_Absolute, text.scene_Relative, text.scene_Leader],
                         cast(u32, scene.links.mode),
                         func|workspace|(index) { workspace.setTimeMode(MediaCommands.TimeValues[index]) })

        page.addAction(text.scene_AlignHere, func|workspace|() { workspace.alignSceneHere() })
        page.addAction(text.scene_AlignSound, func|workspace|() { workspace.alignSceneSound() })
        page.addHeading(text.scene_AtEnd)
        for mode in [SceneEndMode.Shortest, .Independent, .LoopLeader] do
            page.addChoice(sceneEndTitle(mode), mode == scene.links.end, func|workspace, mode|() { workspace.setEndMode(mode) })
        page.addAction(text.scene_Solo, func|workspace|() { workspace.toggleSolo() })
    }
}
