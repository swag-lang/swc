#global internal

using Core, Gui

// One scrolled viewport of a view, found again through the child indices that lead to it.
struct ViewerScrollState
{
    path:     Array'u32
    position: Math.Point
}

// A reload keeps the selected viewer, its reading scale, and each scrolled viewport.
//
// Paths contain child indices, never pointers into the retired window tree.
struct ViewerReadingState
{
    viewer:        String
    query:         String
    scrolls:       Array'ViewerScrollState
    zoom:          u32  = 100
    wrapping:      bool = true
    restoring:     bool
    contentSettingsApplied: bool
    imageZoom:     f32  = 1
    imageFitted:   bool = true
    imagePan:      Math.Point
    imageRotation: u32
    imageMirrored: bool
    pdfZoom:       f32  = 1
    pdfZoomMode:   PdfZoomMode
    pdfLayout:     PdfPageLayout
    page:          u64
    seconds:       f64
    playing:       bool
    muted:         bool
    volume:        f32  = 1
    playbackRate:  f64  = 1
}

impl ViewerReadingState
{
    private mtd captureScrolls(wnd: *Wnd, path: *Array'u32)
    {
        if wnd is ScrollWnd as scroll
        {
            .scrolls.add({path[], scroll.scrollPosition()})
            return
        }

        for child, index in wnd.children
        {
            path.add(cast(u32, index))
            .captureScrolls(child[], path)
            discard path.popBack()
        }
    }

    // Records what `session` shows, under the viewer `key` and the active `search`, before a reload.
    mtd capture(session: *ViewerSession, key, search: string)
    {
        .viewer = key
        .query  = search
        .scrolls.clear()
        var path: Array'u32
        .captureScrolls(session.view!, &path)
        switch session.view
        {
        case Viewers.PlainText.Panel as view:
            .zoom     = view.zoomPercent
            .wrapping = view.wrapping

        case Viewers.Code.Panel as view:
            .zoom = view.zoomPercent

        case Viewers.Html.Panel as view:
            .zoom = view.zoomPercent

        case Viewers.OpenDocument.Panel as view:
            .zoom = view.zoomPercent

        case Viewers.PdfDocument.Panel as view:
            .pdfZoom     = view.pdfView.zoom
            .pdfZoomMode = view.pdfView.zoomMode
            .pdfLayout   = view.pdfView.pageLayout
            .page        = view.pdfView.pageIndex

        case Viewers.Picture.Panel as view:
            .imageZoom     = view.imageView.zoom
            .imageFitted   = view.imageView.isFitted
            .imagePan      = view.imageView.panOffset
            .imageRotation = view.imageView.rotationQuarterTurns
            .imageMirrored = view.imageView.isMirrored

        case Viewers.Sound.Panel as view:
            .seconds = view.voice ? view.voice.playbackPositionSeconds() : cast(f64, view.elapsed)
            .playing = view.playing
            .volume  = view.volume
            .muted   = view.muted

        case Viewers.Film.Panel as view:
            .seconds      = view.currentSeconds()
            .playing      = view.playing
            .volume       = view.volume
            .muted        = view.muted
            .playbackRate = view.playbackRate
        }

        if key == "markdown" and session.info do
            .zoom = assume cast(*Viewers.MarkdownText.ZoomButton, session.info.children[0]).zoomPercent
    }

    // Applies the recorded reading scale to the reloaded `session`, then arms [[ViewerReadingState.restore]].
    mtd applySettings(session: *ViewerSession)
    {
        switch session.view!
        {
        case Viewers.PlainText.Panel as view:
            view.setZoom(.zoom)
            if view.wrapping != .wrapping do
                view.toggleWrap()

        case Viewers.Code.Panel as view:
            view.setZoom(.zoom)

        case Viewers.Html.Panel as view:
            view.setZoom(.zoom)

        case Viewers.OpenDocument.Panel as view:
            view.setZoom(.zoom)
        }

        if .viewer == "markdown" and session.info do
            assume cast(*Viewers.MarkdownText.ZoomButton, session.info.children[0]).applyZoom(.zoom)
        .restoring = true
        .contentSettingsApplied = false
    }

    // Brings the recorded position back to the reloaded `session`, and reports whether it is done.
    //
    // It waits for the initial viewport, applies the saved position once, then lets streaming settle.
    mtd restore(session: *ViewerSession)->bool
    {
        if not session.view do
            return true
        if session.isLoading and session.isLoading() do
            return false
        if .contentSettingsApplied do
            return true

        // Reapplying an unreachable position interrupts the viewer's own seek and scroll
        // animation on every watch tick, so a shorter replacement can never finish loading.
        .contentSettingsApplied = true
        switch session.view
        {
        case Viewers.PdfDocument.Panel as view:
            view.pdfView.setPageLayout(.pdfLayout)
            view.pdfView.setZoom(.pdfZoom)
            view.pdfView.setZoomMode(.pdfZoomMode)
            view.pdfView.showPage(.page)

        case Viewers.Picture.Panel as view:
            if .imageMirrored do
                view.imageView.mirrorHorizontally()
            for .imageRotation do
                view.imageView.rotateClockwise()
            if .imageFitted do
                view.imageView.zoomToFit()
            else do
                view.imageView.setZoom(.imageZoom)
            view.imageView.setPanOffset(.imagePan)

        case Viewers.Sound.Panel as view:
            view.setVolume(.volume)
            view.setMuted(.muted)
            view.seekSeconds(cast(f32, .seconds))
            if view.playing != .playing do
                view.togglePlayback()

        case Viewers.Film.Panel as view:
            view.setVolume(.volume)
            view.setMuted(.muted)
            view.setPlaybackRate(.playbackRate)
            view.seekSeconds(.seconds)
            if view.playing != .playing do
                view.togglePlayback()
        }

        for saved in .scrolls
        {
            var wnd = session.view
            for index in saved.path
            {
                if index >= wnd.children.count
                {
                    wnd = null
                    break
                }

                wnd = wnd!.children[index]
            }

            if wnd
            {
                if wnd is ScrollWnd as scroll do
                    scroll.setScrollPos(saved.position)
            }
        }

        return not session.isLoading or not session.isLoading()
    }
}
