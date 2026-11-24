#global internal

using Core, Gui

namespace MediaCommands
{
    const Links      = "scope.scene.links"
    const Transport  = "scope.scene.transport"
    const Play       = "scope.scene.play"
    const Pause      = "scope.scene.pause"
    const Stop       = "scope.scene.stop"
    const Linked     = "scope.scene.link"
    const Time       = "scope.scene.link.time"
    const Playback   = "scope.scene.link.playback"
    const Framing    = "scope.scene.link.framing"
    const Scroll     = "scope.scene.link.scroll"
    const AlignHere  = "scope.scene.alignHere"
    const AlignSound = "scope.scene.alignSound"
    const Solo       = "scope.scene.solo"
    const Times      = ["scope.scene.absolute", "scope.scene.relative", "scope.scene.leader"]
    const Ends       = ["scope.scene.stopShortest", "scope.scene.stopIndependently", "scope.scene.loopLeader"]
    const TimeValues = [SceneTimeMode.Absolute, .Relative, .Leader]
    const EndValues  = [SceneEndMode.Shortest, .Independent, .LoopLeader]
    const PlayModes  = ["scope.scene.playOnce", "scope.scene.repeat", "scope.scene.playFolder", "scope.scene.shuffle"]
    const Axes       = [Linked, Time, Playback, Framing, Scroll]
}

func sceneTimeTitle(mode: SceneTimeMode)->string
{
    switch #complete mode
    {
    case .Absolute: return appStrings().scene_Absolute
    case .Relative: return appStrings().scene_Relative
    case .Leader:   return appStrings().scene_Leader
    }
}

func sceneEndTitle(mode: SceneEndMode)->string
{
    switch #complete mode
    {
    case .Shortest:    return appStrings().scene_Shortest
    case .Independent: return appStrings().scene_Independent
    case .LoopLeader:  return appStrings().scene_LoopLeader
    }
}

func sceneEndIcon(mode: SceneEndMode)->ThemeIcons
{
    switch #complete mode
    {
    case .Shortest:    return .Stop
    case .Independent: return .PlayOnce
    case .LoopLeader:  return .RepeatAll
    }
}

impl ViewerWorkspace
{
    mtd setSceneLink(id: WndId, on: bool)
    {
        let scene = .scene()
        if not scene do
            return
        let wasFramingLinked = scene.linked and scene.links.framing
        switch id
        {
        case MediaCommands.Linked:   scene.linked = on
        case MediaCommands.Time:     scene.links.time = on
        case MediaCommands.Playback: scene.links.playback = on
        case MediaCommands.Framing:  scene.links.framing = on
        case MediaCommands.Scroll:   scene.links.scroll = on
        default: return
        }

        let framingLinked = scene.linked and scene.links.framing
        if wasFramingLinked != framingLinked and .comparisonVisible() and .comparison!.isPicture() do
            .comparison!.synchronizePictureFraming(fromRight: framingLinked and scene.active == 1)
        .updateMedia()
        .refreshMediaCaptions()
        .invalidate()
        .linkReading(.activeDocument())
        catch .primary.saveState()
    }

    mtd setTimeMode(mode: SceneTimeMode)
    {
        let scene = unwrap .scene()
        scene.links.mode   = mode
        scene.linked       = true
        scene.links.time   = true
        scene.links.leader = mode == .Leader ? scene.active : Swag.U64.Max
        .refreshMediaCaptions()
        .invalidate()
        catch .primary.saveState()
    }

    mtd setEndMode(mode: SceneEndMode)
    {
        let scene = unwrap .scene()
        scene.links.end = mode
        if mode != .Independent
        {
            scene.linked         = true
            scene.links.playback = true
        }
        .synchronizeMedia()
        catch .primary.saveState()
    }

    mtd toggleSolo()
    {
        let scene = unwrap .scene()
        scene.links.solo = scene.links.solo == scene.active ? Swag.U64.Max : scene.active
        .synchronizeMedia()
        catch .primary.saveState()
    }

    mtd routeSceneMediaKey(evt: *KeyEvent, source: *Wnd)->bool
    {
        let scene = .scene()
        if not scene or scene.views.count < 2 or source is EditBox or .activeDocument().lens.isOpen() do
            return false
        if evt.modifiers == .None and evt.key == .L and .hasViewLinks()
        {
            .setSceneLink(MediaCommands.Linked, not scene.linked)
            return true
        }

        let groupToggle = evt.modifiers == .Shift and evt.key == .Space and .canPlayScene()
        let linkedToggle = evt.modifiers == .None and
                           (evt.key == .Space or evt.key == .MediaPlayPause) and
                           .usesLinkedTransport(scene)
        if groupToggle or linkedToggle
        {
            if not .mediaPlayKeyDown do
                .playScene(all: true)
            .mediaPlayKeyDown = true
            return true
        }

        if not .isMediaScene() do
            return false
        if evt.modifiers == .None and not .focusOnGrid
        {
            switch evt.key
            {
            case .A:     .alignSceneHere()
            default:     return false
            }

            return true
        }

        if evt.modifiers == .Control and
           (evt.key == .Left or evt.key == .Right) and
           scene.linked and
           scene.links.playback
        {
            let player = ScenePlayer.from(scene.views[.mediaLeader(scene)].document)
            if not player.film or not player.ready() do
                return false
            let film = player.film
            let last = film.video.frameCount()
            let next = evt.key == .Right ? (last ? Math.min(film.frameIndex + 1, last - 1) : film.frameIndex + 1) :
                       (film.frameIndex ? film.frameIndex - 1 : 0)
            for view in scene.views do
                ScenePlayer.from(view.document).setPlaying(false)
            let relative = scene.links.mode == .Relative
            let position = film.frameSeconds(next)
            for view, index in scene.views
            {
                let target = position + (relative ? view.offset - scene.views[.mediaLeader(scene)].offset : 0)
                if index == .mediaLeader(scene) do
                    film.seekFrame(next)
                elif scene.links.time do
                    ScenePlayer.from(view.document).seek(target)
            }

            return true
        }

        return false
    }
}

impl ViewerWindow
{
    mtd addMediaCommands()
    {
        let group = func()->string => appStrings().scene_Transport
        .lens.addCommands(func()->string => appStrings().lens_View, [MediaCommands.Transport])
        .lens.addCommands(group, [MediaCommands.Play, MediaCommands.Pause, MediaCommands.Stop])
        .lens.addCommands(group, MediaCommands.PlayModes)
        let title = func()->string => appStrings().scene_Linked
        .lens.addCommands(title, [MediaCommands.Links])
        .lens.addCommands(title, MediaCommands.Axes)
        .lens.addCommands(title, MediaCommands.Times)
        .lens.addCommands(title, MediaCommands.Ends)
        .lens.addCommands(title, [MediaCommands.AlignHere, MediaCommands.AlignSound, MediaCommands.Solo])
    }

    mtd computeMediaCommand(evt: *CommandStateEvent)->bool
    {
        let workspace = .workspace
        if not workspace do
            return false
        let scene        = workspace.scene()
        let text         = appStrings()
        var name: string = ""
        var hidden       = not workspace.isMediaScene()
        var checked      = false
        var checkable    = true
        var icon         = ThemeIcons.Link
        switch evt.id
        {
        case MediaCommands.Transport:
            name      = text.scene_Controls
            icon      = .Grid
            hidden    = not scene or scene.views.count < 2
            checkable = false

        case MediaCommands.Links:
            name      = workspace.isMediaScene() ? text.scene_Links : text.scene_ViewLinks
            hidden    = not workspace.hasViewLinks()
            checkable = false

        case MediaCommands.Play, MediaCommands.Pause, MediaCommands.Stop:
            name      = evt.id == MediaCommands.Play ? text.scene_Play : (evt.id == MediaCommands.Pause ? text.scene_Pause : text.scene_Stop)
            icon      = evt.id == MediaCommands.Play ? .Play : (evt.id == MediaCommands.Pause ? .Pause : .Stop)
            hidden    = not workspace.canPlayScene()
            checkable = false
            evt.disabled = hidden or not workspace.canRunTransport(evt.id)
            evt.updatedFields.add(.Disabled)

        case MediaCommands.Linked:
            name    = text.scene_Linked
            checked = scene and scene.linked
            hidden  = not workspace.hasViewLinks()

        case MediaCommands.Time:
            icon    = .GoTo
            name    = text.scene_LinkTime
            checked = scene and scene.links.time

        case MediaCommands.Playback:
            icon    = .Play
            name    = text.scene_LinkPlayback
            checked = scene and scene.links.playback

        case MediaCommands.Framing:
            icon    = .FitView
            name    = text.scene_LinkFraming
            checked = scene and scene.links.framing
            hidden  = not scene or scene.views.count < 2 or not workspace.canLinkFraming()

        case MediaCommands.Scroll:
            icon    = .LineNumbers
            name    = text.scene_LinkScroll
            checked = scene and scene.links.scroll
            hidden  = not scene or scene.views.count < 2 or not workspace.canLinkScroll()

        case MediaCommands.AlignHere:
            icon      = .GoTo
            name      = text.scene_AlignHere
            checkable = false

        case MediaCommands.AlignSound:
            icon      = .AudioTracks
            name      = text.scene_AlignSound
            checkable = false

        case MediaCommands.Solo:
            icon    = .Volume
            name    = text.scene_Solo
            checked = scene and scene.links.solo == scene.active

        default:
            for id, index in MediaCommands.PlayModes where id == evt.id
            {
                let mode = Viewer.PlayModeValues[index]
                hidden  = not workspace.hasSceneTransport()
                name    = Viewer.playModeText(mode)
                icon    = Viewer.playModeIcon(mode)
                checked = not hidden and workspace.scenePlayModeIs(mode)
            }

            for id, index in MediaCommands.Times where id == evt.id
            {
                let mode = MediaCommands.TimeValues[index]
                name    = sceneTimeTitle(mode)
                checked = scene and scene.links.mode == mode
            }

            for id, index in MediaCommands.Ends where id == evt.id
            {
                let mode = MediaCommands.EndValues[index]
                icon    = sceneEndIcon(mode)
                name    = sceneEndTitle(mode)
                checked = scene and workspace.effectiveEndMode(scene) == mode
            }
        }

        if not name.count do
            return false
        evt.name          = name
        evt.hidden        = hidden
        evt.icon          = .theme().icon(icon, .themeMetrics().menuPopup_IconSize)
        evt.updatedFields |= .Name | .Hidden | .Icon
        if checkable
        {
            evt.checked = checked
            evt.updatedFields.add(.Checked)
        }

        evt.accepted = true
        return true
    }

    mtd runMediaCommand(id: WndId)->bool
    {
        let workspace = .workspace
        let scene     = workspace?.scene()
        if not workspace or not scene or scene.views.count < 2 do
            return false
        switch id
        {
        case MediaCommands.Transport:
            workspace.showMediaTransport()

        case MediaCommands.Links:
            if workspace.hasViewLinks() do
                workspace.showMediaLinks()

        case MediaCommands.Play, MediaCommands.Pause:
            if workspace.canPlayScene() do
                workspace.setScenePlaying(id == MediaCommands.Play)

        case MediaCommands.Stop:
            if workspace.canPlayScene() do
                workspace.stopScene()

        case MediaCommands.Linked:
            workspace.setSceneLink(id, not scene.linked)

        case MediaCommands.Time:
            workspace.setSceneLink(id, not scene.links.time)

        case MediaCommands.Playback:
            workspace.setSceneLink(id, not scene.links.playback)

        case MediaCommands.Framing:
            workspace.setSceneLink(id, not scene.links.framing)

        case MediaCommands.Scroll:
            workspace.setSceneLink(id, not scene.links.scroll)

        case MediaCommands.AlignHere:
            workspace.alignSceneHere()

        case MediaCommands.AlignSound:
            workspace.alignSceneSound()

        case MediaCommands.Solo:
            workspace.toggleSolo()

        default:
            for item, index in MediaCommands.PlayModes where item == id and workspace.hasSceneTransport()
            {
                workspace.setScenePlayMode(Viewer.PlayModeValues[index])
                return true
            }

            for item, index in MediaCommands.Times where item == id
            {
                workspace.setTimeMode(MediaCommands.TimeValues[index])
                return true
            }

            for item, index in MediaCommands.Ends where item == id
            {
                workspace.setEndMode(MediaCommands.EndValues[index])
                return true
            }

            return false
        }

        return true
    }
}
