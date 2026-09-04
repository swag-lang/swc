using Core, Pixel, Gui

const ViewerDropHighlightInset = 16.0
const ViewerDropHighlightWash  = 0.12'f32

// Highlights the document while a desktop file can be dropped on Swag Scope.
//
// This is only a gesture affordance. It accepts no pointer input and disappears before the normal
// file-opening path starts, so the viewer receives a drop exactly as it did before the highlight.
struct ViewerDropHighlight
{
    using wnd: Wnd

    late prompt: *Label
}

impl IWnd for ViewerDropHighlight
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        var rect    = .clientRect()
        rect.applyPadding({ViewerDropHighlightInset, ViewerDropHighlightInset, ViewerDropHighlightInset, ViewerDropHighlightInset})
        if rect.isEmpty() do
            return

        let corner = .themeRects().panel_Bk.radius
        let wash   = colors.hilight.withAlpha(cast(u8) (cast(f32) colors.hilight.a * ViewerDropHighlightWash))
        painter.fillRoundRect(rect, corner, corner, wash)

        var pen = Pen.createSolid(colors.hilight, 2)
        pen.borderPos = .Inside
        painter.drawRoundRect(rect, corner, corner, pen)
    }
}

impl ViewerDropHighlight
{
    func create(parent: *Wnd)->*ViewerDropHighlight
    {
        let result = Wnd.create'ViewerDropHighlight(parent, "scope.drop.highlight")
        result.dockStyle       = .Center
        result.backgroundStyle = .Transparent
        result.wndFlags        |= WndFlags.TopMost | WndFlags.Disabled

        with result.prompt = Label.create(result, appStrings().ui_DropTitle)
        {
            .dockStyle = .Center
            .style.setFont(result.theme().createDefaultFont(16, .Bold), .Regular)
            .setTextAlignment(.Center, .Center)
        }

        result.refreshTheme()
        result.hide()
        return result
    }

    // Keeps the empty-state invitation readable by relying on its existing title. A document
    // already on screen has no such invitation, so the overlay supplies its own short prompt.
    mtd showTarget(showPrompt: bool)
    {
        .prompt.show(showPrompt)

        // Hidden children are deliberately skipped by their parent's layout pass. Size the layer
        // before revealing it so the very first drag enter can paint the complete document target.
        .setPosition(.parent!.clientRect())
        .show()
        .bringToFront()
    }

    mtd retranslate()
    {
        .prompt.setText(appStrings().ui_DropTitle)
    }

    mtd refreshTheme()
    {
        .prompt.setTextColor(.themeColors().hilight)
    }
}
