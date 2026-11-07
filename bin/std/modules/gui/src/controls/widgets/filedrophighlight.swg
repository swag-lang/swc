#global public

using Core, Pixel

private const FileDropHighlightInset = 16.0
private const FileDropHighlightWash  = 0.12'f32

// Marks a window as the target of a desktop file drag with a Voltage outline and a soft wash.
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
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        var rect    = .clientRect()
        rect.applyPadding(Math.Vector4{FileDropHighlightInset, FileDropHighlightInset, FileDropHighlightInset, FileDropHighlightInset})
        if rect.isEmpty() do
            return

        let corner = .themeRects().panel_Bk.radius
        let wash   = colors.signature.withAlpha(cast(u8, (cast(f32, colors.signature.a) * FileDropHighlightWash)))
        painter.fillRoundRect(rect, corner, corner, wash)

        var pen = Pen.createSolid(colors.signature, 2)
        pen.borderPos = .Inside
        painter.drawRoundRect(rect, corner, corner, pen)
    }
}

impl FileDropHighlight
{
    // Creates a hidden overlay that fills `parent` and displays `prompt` while a file is dragged.
    func create(parent: *Wnd, prompt: string, id: WndId? = null)->*FileDropHighlight
    {
        with let result = Wnd.create'FileDropHighlight(parent, null, {}, id)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .wndFlags        |= WndFlags.TopMost | WndFlags.Disabled
        }

        with result.prompt = Label.create(result, prompt)
        {
            .dockStyle = .Center
            .style.setFont(result.theme().createDefaultFont(16, .Bold), .Regular)
            .setTextAlignment(.Center, .Center)
        }

        result.refreshTheme()
        result.hide()
        return result
    }

    // Reveals the target, with its prompt only when the underlying content needs an invitation.
    mtd showTarget(showPrompt: bool)
    {
        .prompt.show(showPrompt)

        // Hidden children are skipped by layout. Size the layer before the first drag-enter paint.
        .setPosition(.parent!.clientRect())
        .show()
        .bringToFront()
    }

    // Replaces the invitation after a language switch.
    mtd setPrompt(text: string)
    {
        .prompt.setText(text)
    }

    // Applies the current theme's Voltage color to the invitation.
    mtd refreshTheme()
    {
        .prompt.setTextColor(.themeColors().signature)
    }
}
