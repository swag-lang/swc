#global public

using Core, Pixel

// Hosts an application action in a surface's caption.
struct CaptionButton
{
    public
    {
        using button: IconButton     // Icon-button behavior and presentation.
    }

    leading: bool
}

impl IWnd for CaptionButton
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        let surface = assume cast(*SurfaceWnd, .parent)
        if .leading do
            surface.unregisterLeadingCaptionButton(me)
        else do
            surface.unregisterCaptionButton(me)
        .button.IWnd.onDestroyEvent(evt)
    }
}

impl CaptionButton
{
    // Shows or hides this action and rearranges the caption before its next paint.
    mtd show(visible = true)
    {
        if .isLocallyVisible() == visible do
            return
        .button.wnd.show(visible)
        .parent!.sendResizeEvent()
    }

    // Hides this action and gives its space back to the caption title.
    mtd hide() => .show(false)

    // Creates a caption action using a theme icon at the caption glyph size.
    //
    // The surface owns the button. Connect [[Gui.Button.sigPressed]] to run the action and set
    // [[Gui.Wnd.toolTip]] to name it.
    #[Swag.Discardable]
    func create(surface: *Surface, icon: ThemeIcons, id: WndId? = null)->*CaptionButton
    {
        return .createAt(surface, icon, id, leading: false)
    }

    // Creates a caption action after the application glyph and before the centred title.
    //
    // The surface owns the button. Connect [[Gui.Button.sigPressed]] to run the action and set
    // [[Gui.Wnd.toolTip]] to name it.
    #[Swag.Discardable]
    func createLeading(surface: *Surface, icon: ThemeIcons, id: WndId? = null)->*CaptionButton
    {
        return .createAt(surface, icon, id, leading: true)
    }

    private func createAt(surface: *Surface, icon: ThemeIcons, id: WndId?, leading: bool)->*CaptionButton
    {
        Swag.assert(surface != null)
        let parent      = assume cast(*SurfaceWnd, surface.wnd)
        with let result = Wnd.create'CaptionButton(parent, null, {}, id)
        {
            .leading = leading
            .button.setIcon(surface.app.theme.icon(icon, surface.app.theme.metrics.wnd_CaptionButtonGlyph))
            .setForm(.RoundedRectangle)
            .focusPolicy = .None
        }

        if leading do
            parent.registerLeadingCaptionButton(result)
        else do
            parent.registerCaptionButton(result)
        return result
    }
}
