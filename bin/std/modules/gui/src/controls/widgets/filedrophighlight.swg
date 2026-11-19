#global public

using Core, Pixel

private const FileDropHighlightWash = 0.12'f32

// Marks a window as the target of a desktop file drag with an outline and an optional invitation.
//
// The layer ignores input. Its parent continues to receive the drag and decides whether to accept
// the file. Show it only for a supported file, and hide it on leave or drop.
struct FileDropHighlight
{
    public using wnd: Wnd     // Embedded window behavior and presentation.

    public late prompt: *Label     // Invitation shown when the underlying content has no drop hint.
}

impl IWnd for FileDropHighlight
{
    mtd impl onLayout()
    {
        .setPosition(.parent!.clientRect(), computeLayout: false)
        if not .prompt.isLocallyVisible() do
            return

        let bounds = .clientRect()
        let inset  = .themeMetrics().floating_Inset
        let size   = .prompt.itf.measureContent({})
        let width  = Math.min(Math.ceil(size.x), Math.max(0, bounds.width - 2 * inset))
        let height = Math.min(Math.ceil(size.y), bounds.height)
        .prompt.setPosition(bounds.horzCenter() - width * 0.5, bounds.vertCenter() - height * 0.5, width, height, computeLayout: false)
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let metrics = .themeMetrics()
        let inset   = painter.hairline(metrics.wnd_BorderSize)
        var rect    = .clientRect()
        rect.inflate(-inset)
        if rect.width <= 0 or rect.height <= 0 do
            return

        let corner = Math.max(0, (.surface?.cornerRadius() orelse metrics.surfaceWnd_CornerRadius) - inset)
        let wash   = colors.signature.withAlpha(cast(u8, (cast(f32, colors.signature.a) * FileDropHighlightWash)))
        painter.fillRoundRect(rect, corner, corner, wash)

        var pen = Pen.createSolid(colors.signature, metrics.focusRing_Size)
        pen.borderPos = .Inside
        painter.drawRoundRect(rect, corner, corner, pen)

        // The prompt needs its own ground over pictures and other variable content.
        if .prompt.isLocallyVisible() and not .prompt.position.isEmpty() do
            painter.fillRoundRect(.prompt.position, metrics.corner_Control, metrics.corner_Control, colors.surface)
    }
}

impl FileDropHighlight
{
    // Creates a hidden overlay that fills `parent` and displays `prompt` while a file is dragged.
    func create(parent: *Wnd, prompt: string, id: WndId? = null)->*FileDropHighlight
    {
        with let result = Wnd.create'FileDropHighlight(parent, null, {}, id)
        {
            .dockStyle       = .Float
            .backgroundStyle = .Transparent
            .wndFlags        |= WndFlags.TopMost | WndFlags.Disabled
        }

        with result.prompt = Label.create(result, prompt, flags: .Ellipsis)
        {
            .padding = result.themeMetrics().toolTip_Padding
            .style.setFont(result.theme().createDefaultFont(result.themeMetrics().defaultFontSize, .Bold), .Regular)
            .setTextAlignment(.Center, .Center)
        }

        result.refreshTheme()
        result.hide()
        return result
    }

    // Reveals the target, with its prompt only when the underlying content needs an invitation.
    mtd showTarget(showPrompt: bool)
    {
        let needsLayout = not .isLocallyVisible() or .prompt.isLocallyVisible() != showPrompt
        .prompt.show(showPrompt)

        // Hidden children are skipped by layout. Size the layer before the first drag-enter paint.
        if needsLayout do
            .itf.onLayout()
        .show()
        .bringToFront()
    }

    // Replaces the invitation after a language switch.
    mtd setPrompt(text: string)
    {
        .prompt.setText(text)
        if .isLocallyVisible() do
            .itf.onLayout()
    }

    // Applies the current theme's primary text color to the invitation.
    mtd refreshTheme()
    {
        .prompt.setTextColor(.themeColors().text)
    }
}
