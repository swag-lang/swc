#global public

using Core, Pixel

// Hosts an application action beside a surface's native caption controls.
struct CaptionButton
{
    public
    {
        using button: IconButton     // Icon-button behavior and presentation.
    }
}

impl IWnd for CaptionButton
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        assume cast(*SurfaceWnd, .parent).unregisterCaptionButton(me)
        .button.IWnd.onDestroyEvent(evt)
    }
}

impl CaptionButton
{
    // Creates a caption action using a theme icon at the caption glyph size.
    //
    // The surface owns the button. Connect [[Gui.Button.sigPressed]] to run the action and set
    // [[Gui.Wnd.toolTip]] to name it.
    #[Swag.Discardable]
    func create(surface: *Surface, icon: ThemeIcons, id: WndId? = null)->*CaptionButton
    {
        Swag.assert(surface != null)
        let parent      = assume cast(*SurfaceWnd, surface.wnd)
        with let result = Wnd.create'CaptionButton(parent, null, {}, id)
        {
            .button.setIcon(surface.app.theme.icon(icon, surface.app.theme.metrics.wnd_CaptionButtonGlyph))
            .setForm(.RoundedRectangle)
            .focusPolicy = .None
        }

        parent.registerCaptionButton(result)
        return result
    }
}
