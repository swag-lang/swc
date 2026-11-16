using Core, Gui, Pixel

// Capture kinds and their compact choices in the in-place overlay.

// The kinds a zone can become, in menu order. A kind joins when it can be taken.
const KindMedia = [CaptureMedia.Picture, CaptureMedia.Animation, CaptureMedia.Video]

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

// Returns the width of the video quality choice, wide enough for each of its names.
func qualityOptionWidth(theme: *Theme)->f32
{
    var widest = 0'f32
    for quality in [VideoQuality.Maximum, .Balanced, .Compact] do
        widest = Math.max(widest, recordOptionWidth(theme, Format.toString(appStrings().ui_AimQuality, quality.label())))
    return widest
}

// Creates the video quality choice of a recording about to start. A press moves to the next
// quality, and the button always names the one the recording will use.
func createQualityOption(parent: *Wnd, options: *CaptureOptions)->*IconButton
{
    let label = Format.toString(appStrings().ui_AimQuality, options.recordVideoQuality.label())
    with let result = createRecordOption(parent, parent.theme().icon(.Settings), label, false, toggle: false)
    {
        .toolTip = appStrings().tip_AimQuality
        .resize(qualityOptionWidth(parent.theme()), .position.height)
        .sigPressed += func|options, result|(_)
        {
            options.recordVideoQuality = options.recordVideoQuality.next()
            result.setText(Format.toString(appStrings().ui_AimQuality, options.recordVideoQuality.label()))
        }
    }

    return result
}

// Side of the dot of a recording on Record.
const RecordDotSize = 8.0

// Returns the width of the Record button: the dot of a recording, small beside the word.
func recordButtonWidth(theme: *Theme)->f32
{
    let metrics = &theme.metrics
    let font    = theme.createDefaultFont(metrics.defaultFontSize)
    return Math.ceil(Painter.measureString(appStrings().ui_AimRecord, font).width +
                     2 * metrics.btnPush_TextMargin + RecordDotSize + metrics.btnIcon_SpacingTextH)
}

// Creates the one primary action of a recording about to start: Record, in words, after its dot.
func createRecordButton(parent: *Wnd)->*PushButton
{
    let metrics = parent.themeMetrics()
    let size    = Math.Rectangle{0, 0, recordButtonWidth(parent.theme()), metrics.miniBar_ButtonSize}
    with let result = PushButton.create(parent, appStrings().ui_AimRecord, size, form: .Strong)
    {
        .setIcon(parent.theme().icon(.Dot, RecordDotSize))
        .setIconSize(RecordDotSize, RecordDotSize)
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
