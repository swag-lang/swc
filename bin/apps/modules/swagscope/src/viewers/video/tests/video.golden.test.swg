#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Video, Audio, Viewers

// Bright, middle, and dark bands: the subtitle text has to stay readable over each picture.
struct SubtitleBackdropProbe
{
    using wnd: Wnd
}

impl IWnd for SubtitleBackdropProbe
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let rect    = .clientRect()
        let band    = Math.floor(rect.width / 3)
        painter.fillRect(0, 0, band, rect.height, Color.fromArgb(0xFFF2EFE6))
        painter.fillRect(band, 0, band, rect.height, Color.fromArgb(0xFF8A8F96))
        painter.fillRect(2 * band, 0, rect.width - 2 * band, rect.height, Color.fromArgb(0xFF101418))
    }
}

func assertVideoTimelineEndpoints(light: bool, golden: string)
{
    var host: Testing.HeadlessHost
    host.setup(420, 90)
    host.root.backgroundStyle = .Application
    if light do
        host.theme.setLight()
    else do
        host.theme.setDark()
    host.notify(.ThemeChanged)

    let start = Wnd.create'Film.VideoTimeline(&host.root, {24, 12, 372, 24})
    let end   = Wnd.create'Film.VideoTimeline(&host.root, {24, 54, 372, 24})
    start.setBounds(0, 100, 0)
    end.setBounds(0, 100, 0)
    start.setValueWithoutGesture(0)
    end.setValueWithoutGesture(100)
    let room = start.clientRect()
    Swag.assert(start.positionOf(0) - room.x >= 7.99)
    Swag.assert(room.right() - end.positionOf(100) >= 7.99)
    host.root.applyLayout()

    var image = host.render(&host.root)
    assertScopeImageGolden(&image, golden)
}

func assertSubtitleEffect(effect: Film.SubtitleEffect, size: Film.SubtitleSize, dpiScale: f32, golden: string)
{
    let savedSettings = Film.g_SubtitleSettings
    defer Film.g_SubtitleSettings = savedSettings
    Film.g_SubtitleSettings        = {}
    Film.g_SubtitleSettings.effect = effect
    Film.g_SubtitleSettings.size   = size

    var host: Testing.HeadlessHost
    host.setup(900, 240, dpiScale)
    let backdrop = Wnd.create'SubtitleBackdropProbe(&host.root)
    backdrop.dockStyle = .Center
    let overlay = Film.SubtitleOverlay.create(backdrop)
    overlay.setSubtitle("Vous ne passerez pas, dit Gandalf.\nTout le monde descend, Jérôme !")
    host.root.applyLayout()

    var image = host.render(&host.root)
    assertScopeImageGolden(&image, golden)
}

// The film in the window, against `scope.video`: the picture alone at rest, and under the
// pointer the top veil with the title and its facts, the bottom veil with the timeline, the
// time under the pointer, the play button, the time in mono and the chips.
#[Swag.TestTag("golden")]
#test
{
    Swag.assert(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()

    for light in [false, true]
    {
        var host: Testing.HeadlessHost
        let window = framedViewerWindow(&host, videoMatroskaFixturePath(), light)
        let view   = assume cast(*Film.Panel, window.instances[window.activeChoiceIndex].view)

        // The film writes its title in the top veil, so the strip leaves it out.
        Swag.assert(host.surfaceWnd.titleHidden)
        waitForVideoFrame(view)
        waitForVideoAudio(view, 2)
        if view.playing do
            view.togglePlayback()
        view.seekFrame(5)
        waitForVideoFrame(view)
        view.refreshTime()
        view.timeline.setValueWithoutGesture(cast(f32, view.frameSeconds(view.frameIndex)))
        host.settleAnimations(window, 4)

        var rest = host.render(&host.surfaceWnd)
        assertScopeImageGolden(&rest, light ? "viewer.video.paper" : "viewer.video.ink")

        // The first movement brings the veils, the next one reads a time on the timeline.
        let timeline   = view.timeline.surfaceRect()
        let trackX     = timeline.x + 8
        let trackWidth = timeline.width - 16
        host.moveMouse(Math.Point{trackX + trackWidth * 0.6, timeline.vertCenter()})
        host.moveMouse(Math.Point{trackX + trackWidth * 0.62, timeline.vertCenter()})
        host.settleAnimations(window, 4)
        var hover = host.render(&host.surfaceWnd)
        assertScopeImageGolden(&hover, light ? "viewer.video.hover.paper" : "viewer.video.hover.ink")
    }
}

// The playhead and its outline stay whole when the track is at its first or last frame.
#[Swag.TestTag("golden")]
#test
{
    assertVideoTimelineEndpoints(false, "viewer.video.timeline.endpoints.encre")
    assertVideoTimelineEndpoints(true, "viewer.video.timeline.endpoints.paper")
}

// Every readability effect over every kind of picture. The outline and the shadow keep their
// proportions from the normal size to the largest one on a high-density screen, and the
// backdrop of two lines is one shape, with no darker band where the lines meet.
#[Swag.TestTag("golden")]
#test
{
    assertSubtitleEffect(.Outline, .Normal, 1, "viewer.video.subtitle.outline")
    assertSubtitleEffect(.Shadow, .Normal, 1, "viewer.video.subtitle.shadow")
    assertSubtitleEffect(.Background, .Normal, 1, "viewer.video.subtitle.background")
    assertSubtitleEffect(.None, .Normal, 1, "viewer.video.subtitle.none")
    assertSubtitleEffect(.Outline, .VeryLarge, 1.5, "viewer.video.subtitle.outline.large.hidpi")
    assertSubtitleEffect(.Shadow, .VeryLarge, 1.5, "viewer.video.subtitle.shadow.large.hidpi")
    assertSubtitleEffect(.Background, .VeryLarge, 1.5, "viewer.video.subtitle.background.large.hidpi")
}

// The options of a film gather the play mode, the speed, the sound track and the subtitles, each
// with the value in force, and the page of a setting lists its choices with the one in force
// checked. The sheet stands on the speed chip of the bottom veil.
#[Swag.TestTag("golden")]
#test
{
    Swag.assert(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()

    var host: Testing.HeadlessHost
    host.setup(ViewerWindow.MinWidth, 450)
    host.setReducedMotion(true)
    host.theme.setDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    with let commands = Wnd.create'Wnd(&host.root, {0, 0, 0, 52})
    {
        .dockStyle       = .Bottom
        .backgroundStyle = .Window
        .padding         = {16, 8, 16, 8}
    }

    var result = openTestViewer(Film.viewerPlugin(), &host.root, videoMatroskaFixturePath(), commandParent: commands)
    Swag.assert(result.view != null)
    let view = assume cast(*Film.Panel, result.view)
    waitForVideoFrame(view)
    waitForVideoAudio(view, 2)
    if view.playing do
        view.togglePlayback()
    view.seekFrame(5)
    waitForVideoFrame(view)
    view.setPlaybackRate(1.5)

    view.dockStyle = .Center
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)

    var rendered: u32
    host.app.sigFrame += func|host = &host, rendered = &rendered|(_)
    {
        let sheet = host.capturedOptionSheet()
        if not sheet or rendered[] == 2 do
            return
        host.finishAnimations()

        if rendered[] == 0
        {
            Swag.assert(sheet.page.rows.count == 4)
            Swag.assert(sheet.page.rows[1].value == "1.5×" and sheet.page.rows[2].value == "Primary")
            var first = host.render()
            assertScopeImageGolden(&first, "viewer.video.options")
            Swag.assert(sheet.activateRow(Film.texts().ui_OptionAudio))
            host.finishAnimations()
        }
        else
        {
            Swag.assert(sheet.page.rows[0].checked and sheet.page.rows[1].detail == "AAC-LC · 2 ch · 44.1 kHz")
            var tracks = host.render()
            assertScopeImageGolden(&tracks, "viewer.video.options.audio")
            sheet.close()
        }

        rendered[] += 1
    }

    view.showOptions()
    host.app.sigFrame.clear()
    Swag.assert(rendered == 2)
}
