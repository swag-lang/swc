using Core, Gui, Pixel

// Capture kinds and their compact choices in the in-place overlay.

// The kinds a zone can become, in menu and Tab order. A kind joins when it can be taken.
const KindMedia = [CaptureMedia.Picture, CaptureMedia.Animation, CaptureMedia.Video]

// Returns the next capture kind for the overlay's Tab key.
func nextCaptureMedia(media: CaptureMedia)->CaptureMedia
{
    for kind, index in KindMedia where kind == media do
        return KindMedia[(index + 1) % KindMedia.count]
    return KindMedia[0]
}

// Returns the name of the kind of capture `media`.
func kindName(media: CaptureMedia)->string
{
    switch #complete media
    {
    case .Picture:   return appStrings().ui_MediaPicture
    case .Animation: return appStrings().ui_MediaAnimation
    case .Video:     return appStrings().ui_MediaVideo
    }
}

// Returns the glyph that identifies a capture kind in its menu and on the zone.
func kindIcon(main: *MainWnd, theme: *Theme, media: CaptureMedia)->Icon
{
    let size = theme.metrics.menuPopup_IconSize
    switch #complete media
    {
    case .Picture:   return main.icon(.Image, size)
    case .Animation: return theme.icon(.Play, size)
    case .Video:     return main.icon(.Video, size)
    }
}

// Stable menu IDs keep the choice independent of its translated name.
func kindMenuId(media: CaptureMedia)->string
{
    switch #complete media
    {
    case .Picture:   return "capture.kind.picture"
    case .Animation: return "capture.kind.animation"
    case .Video:     return "capture.kind.video"
    }
}

// The widget owns painting, pointer capture, keyboard activation and checked state.
func createRecordOption(parent: *Wnd, icon: Icon, label: string, checked: bool, enabled = true, toggle = true)->*IconButton
{
    let metrics = parent.themeMetrics()
    with let result = IconButton.create(parent, icon, {0, 0, 0, metrics.miniBar_ButtonSize},
                                        flags: toggle ? .Toggle : .None)
    {
        .setIconSize(metrics.menuPopup_IconSize, metrics.menuPopup_IconSize)
        .setTextPosition(.Right)
        .setText(label)
        if toggle do
            .setChecked(checked)
        .enable(enabled)
        .resize(Math.ceil(.itf.measureContent({}).x), metrics.miniBar_ButtonSize)
    }
    return result
}

// Reserve the same content width before the preparation window creates its buttons.
func recordOptionWidth(theme: *Theme, label: string)->f32
{
    let metrics = &theme.metrics
    let font    = theme.createDefaultFont(metrics.defaultFontSize)
    return Math.ceil(2 * metrics.btnIcon_Padding + metrics.menuPopup_IconSize +
                     metrics.btnIcon_SpacingTextH + Painter.measureString(label, font).width)
}
