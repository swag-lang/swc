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
    viewer: String
    query:  String
    #[Serialization.NoSerialize]
    useSavedViewer:         bool
    hasSearchSettings:      bool
    searchMatchCase:        bool
    searchWholeWord:        bool
    searchRegex:            bool
    searchFilter:           bool
    scrolls:                Array'ViewerScrollState
    zoom:                   u32  = 100
    wrapping:               bool = true
    panelOpen:              bool
    restoring:              bool
    contentSettingsApplied: bool
    imageZoom:              f32  = 1
    imageFitted:            bool = true
    imagePan:               Math.Point
    imageRotation:          u32
    imageMirrored:          bool
    pdfZoom:                f32  = 1
    pdfZoomMode:            PdfZoomMode
    pdfLayout:              PdfPageLayout
    page:                   u64
    seconds:                f64
    playing:                bool
    muted:                  bool
    volume:                 f32  = 1
    playbackRate:           f64  = 1
    subtitleDelay:          f64

    // Navigation history belongs to the document session and survives tab switches.
    #[Serialization.NoSerialize]
    soundBackHistory: Array'f32
    #[Serialization.NoSerialize]
    soundForwardHistory: Array'f32
    #[Serialization.NoSerialize]
    hexHistory: Array'u64
    #[Serialization.NoSerialize]
    hexHistoryIndex: u64 = Swag.U64.Max
    #[Serialization.NoSerialize]
    hexCaret: u64
    textBookmarks: Array'Viewers.PlainText.Bookmark
    textBookmarkIdentity: String
    textBookmarksPersistable: bool = true
}

impl ViewerReadingState
{
    private mtd captureScrolls(wnd: *Wnd, path: *Array'u32)
    {
        if wnd is ScrollWnd as scroll
        {
            .scrolls.add(ViewerScrollState{path[], scroll.scrollPosition()})
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
        .viewer    = key
        .query     = search
        .panelOpen = session.sidePanelButton?.isChecked orelse false
        .scrolls.clear()
        .textBookmarks.clear()
        .textBookmarkIdentity = ""
        var path: Array'u32
        .captureScrolls(unwrap session.view, &path)
        switch session.view
        {
        case Viewers.PlainText.Panel as view:
            .zoom     = view.zoomPercent
            .wrapping = view.wrapping
            for bookmark in view.bookmarks do
                .textBookmarks.add(bookmark)
            .textBookmarkIdentity = view.bookmarkIdentity
            .textBookmarksPersistable = view.bookmarksPersistable

        case Viewers.Code.Panel as view:
            .zoom = view.zoomPercent

        case Viewers.Html.Panel as view:
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

        case Viewers.Hex.Panel as view:
            .hexHistory      = view.navigationHistory
            .hexHistoryIndex = view.navigationIndex
            .hexCaret        = view.grid.caret

        case Viewers.Sound.Panel as view:
            .soundBackHistory    = view.backHistory
            .soundForwardHistory = view.forwardHistory
            .seconds             = cast(f64, view.playbackPosition())
            .playing             = view.playing
            .volume              = view.volume
            .muted               = view.muted
            .playbackRate        = view.playbackRate

        case Viewers.Film.Panel as view:
            .seconds       = view.currentSeconds()
            .playing       = view.playing
            .volume        = view.volume
            .muted         = view.muted
            .playbackRate  = view.playbackRate
            .subtitleDelay = view.subtitleDelay
        }

        if key == "markdown" and session.info do
            .zoom = assume cast(*Viewers.MarkdownText.ZoomButton, session.info.children[0]).zoomPercent
    }

    mtd captureSearchSettings(window: const *ViewerWindow)
    {
        .hasSearchSettings = true
        .searchMatchCase   = window.searchMatchCaseOption
        .searchWholeWord   = window.searchWholeWordOption
        .searchRegex       = window.searchRegexOption
        .searchFilter      = window.searchFilterMode
    }

    mtd const restoreSearch(window: *ViewerWindow)
    {
        if .hasSearchSettings
        {
            window.searchMatchCaseOption = .searchMatchCase
            window.searchWholeWordOption = .searchWholeWord
            window.searchRegexOption     = .searchRegex
            window.searchFilterMode      = .searchFilter
        }

        window.searchBox.setText(.query, notify: false)
        window.restartSearch(keepPosition: true)
    }

    // Applies the recorded reading scale to the reloaded `session`, then arms [[ViewerReadingState.restore]].
    mtd applySettings(session: *ViewerSession)
    {
        switch unwrap session.view
        {
        case Viewers.PlainText.Panel as view:
            view.setZoom(.zoom, remember: false)
            if view.wrapping != .wrapping do
                view.toggleWrap()

        case Viewers.Code.Panel as view:
            view.setZoom(.zoom, remember: false)

        case Viewers.Html.Panel as view:
            view.setZoom(.zoom, remember: false)
        }

        if .viewer == "markdown" and session.info do
            assume cast(*Viewers.MarkdownText.ZoomButton, session.info.children[0]).applyZoom(.zoom, remember: false)
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
        let sound = session.view is Viewers.Sound.Panel

        // Sound can seek once the file opens, while the waveform builds in the background.
        if session.view is Viewers.Sound.Panel as audio
        {
            if not audio.openFinished do
                return false
        }
        elif session.isLoading and session.isLoading()
        {
            return false
        }

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

        case Viewers.PlainText.Panel as view:
            view.restoreBookmarks(.textBookmarks.toSlice(), .textBookmarkIdentity)
            view.bookmarksPersistable = .textBookmarksPersistable

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

        case Viewers.Hex.Panel as view:
            view.navigationHistory = .hexHistory
            view.navigationIndex   = .hexHistoryIndex
            view.grid.moveCaret(.hexCaret, false)

        case Viewers.Sound.Panel as view:
            view.backHistory    = .soundBackHistory
            view.forwardHistory = .soundForwardHistory
            view.setVolume(.volume)
            view.setMuted(.muted)
            view.setPlaybackRate(.playbackRate)
            view.seekSeconds(cast(f32, .seconds), remember: false)
            if view.playing != .playing do
                view.togglePlayback()

        case Viewers.Film.Panel as view:
            view.setVolume(.volume)
            view.setMuted(.muted)
            view.setPlaybackRate(.playbackRate)
            view.subtitleDelay = .subtitleDelay
            view.seekSeconds(.seconds)
            if view.playing != .playing do
                view.togglePlayback()
        }

        session.sidePanelButton?.setChecked(.panelOpen)

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

        return sound or not session.isLoading or not session.isLoading()
    }
}
