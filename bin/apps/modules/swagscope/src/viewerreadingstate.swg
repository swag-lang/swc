#global internal

using Core, Gui

struct ViewerScrollState
{
    path:     Array'u32
    position: Math.Point
}

// A reload keeps the selected viewer, its reading scale, and each scrolled viewport.
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
        switch wnd.itf
        {
        case ScrollWnd as scroll:
            .scrolls.add({path[], scroll.scrollPosition()})
            return
        }

        for child, index in wnd.children
        {
            path.add(cast(u32) index)
            .captureScrolls(child[], path)
            path.removeAtOrdered(path.count - 1)
        }
    }

    mtd capture(session: *ViewerSession, key, search: string)
    {
        .viewer = key
        .query  = search
        .scrolls.clear()
        var path: Array'u32
        .captureScrolls(session.view!, &path)
        switch session.view!.itf
        {
        case TextView as view:
            .zoom     = view.zoomPercent
            .wrapping = view.wrapping

        case CodeViewer as view:
            .zoom = view.zoomPercent

        case HtmlViewer as view:
            .zoom = view.zoomPercent

        case OpenDocumentViewer as view:
            .zoom = view.zoomPercent

        case PdfViewer as view:
            .pdfZoom     = view.pdfView.zoom
            .pdfZoomMode = view.pdfView.zoomMode
            .pdfLayout   = view.pdfView.pageLayout
            .page        = view.pdfView.pageIndex

        case ImageViewer as view:
            .imageZoom     = view.imageView.zoom
            .imageFitted   = view.imageView.isFitted
            .imagePan      = view.imageView.panOffset
            .imageRotation = view.imageView.rotationQuarterTurns
            .imageMirrored = view.imageView.isMirrored

        case SoundViewer as view:
            .seconds = view.voice ? view.voice!.playbackPositionSeconds() : cast(f64) view.elapsed
            .playing = view.playing
            .volume  = view.volume
            .muted   = view.muted

        case VideoViewer as view:
            .seconds      = view.currentSeconds()
            .playing      = view.playing
            .volume       = view.volume
            .muted        = view.muted
            .playbackRate = view.playbackRate
        }

        if key == "markdown" and session.info do
            .zoom = (cast(*MarkdownZoomButton) session.info!.children[0]).zoomPercent
    }

    mtd applySettings(session: *ViewerSession)
    {
        switch session.view!.itf
        {
        case TextView as view:
            view.setZoom(.zoom)
            if view.wrapping != .wrapping do
                view.toggleWrap()

        case CodeViewer as view:
            view.setZoom(.zoom)

        case HtmlViewer as view:
            view.setZoom(.zoom)

        case OpenDocumentViewer as view:
            view.setZoom(.zoom)
        }

        if .viewer == "markdown" and session.info do
            (cast(*MarkdownZoomButton) session.info!.children[0]).applyZoom(.zoom)
        .restoring = true
        .contentSettingsApplied = false
    }

    // Wait for the initial viewport, apply the saved position once, then let streaming settle.
    mtd restore(session: *ViewerSession)->bool
    {
        if not session.view do
            return true
        if session.isLoading and session.isLoading!(session.view!) do
            return false
        if .contentSettingsApplied do
            return true

        // Reapplying an unreachable position interrupts the viewer's own seek and scroll
        // animation on every watch tick, so a shorter replacement can never finish loading.
        .contentSettingsApplied = true
        switch session.view!.itf
        {
        case PdfViewer as view:
            view.pdfView.setPageLayout(.pdfLayout)
            view.pdfView.setZoom(.pdfZoom)
            view.pdfView.setZoomMode(.pdfZoomMode)
            view.pdfView.showPage(.page)

        case ImageViewer as view:
            if .imageMirrored do
                view.imageView.mirrorHorizontally()
            for .imageRotation do
                view.imageView.rotateClockwise()
            if .imageFitted do
                view.imageView.zoomToFit()
            else do
                view.imageView.setZoom(.imageZoom)
            view.imageView.setPanOffset(.imagePan)

        case SoundViewer as view:
            view.setVolume(.volume)
            view.setMuted(.muted)
            view.seekSeconds(cast(f32) .seconds)
            if view.playing != .playing do
                view.togglePlayback()

        case VideoViewer as view:
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
                if index >= wnd!.children.count
                {
                    wnd = null
                    break
                }

                wnd = wnd!.children[index]
            }

            if wnd
            {
                switch wnd!.itf
                {
                case ScrollWnd as scroll: scroll.setScrollPos(saved.position)
                }
            }
        }

        return not session.isLoading or not session.isLoading!(session.view!)
    }
}
