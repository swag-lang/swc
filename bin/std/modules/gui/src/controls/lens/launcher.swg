#global public
#global namespace Lens

using Core, Pixel

// Opens an application's lens through a named Commands button in its caption strip.
struct Launcher
{
    public using captionButton: Gui.CaptionButton     // Embedded caption-button behavior and presentation.
    command: String
}

impl IWnd for Launcher
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .ThemeChanged or evt.kind == .LanguageChanged do
            .refreshLabel()
        evt.accepted = false
    }
}

impl Launcher
{
    // Creates a caption action that posts `command` to `owner`.
    //
    // The surface owns the button, and `owner` must outlive it. The command identifier is copied.
    // Route the same command from Ctrl Space so pointer and keyboard activation share behavior.
    // The label follows the application language and its width follows the theme metrics.
    #[Swag.Discardable]
    func create(owner: *Wnd, command: WndId)->*Launcher
    {
        let surface     = unwrap owner.surface
        let parent      = assume cast(*SurfaceWnd, surface.wnd)
        with let result = Wnd.create'Launcher(parent)
        {
            .owner   = owner
            .command = command
            .setForm(.RoundedRectangle)
            .setTextPosition(.Right)
            .focusPolicy = .Tab
            .wndFlags.add(.ActivatesOnKey)
            .sigPressed += func|result|(_) { result.owner!.postCommandEvent(result.command) }
            .refreshLabel()
        }

        parent.registerCaptionButton(result)
        return result
    }

    private mtd refreshLabel()
    {
        let metrics = .themeMetrics()
        .captionButton.button.setIcon(.theme().icon(.Search, metrics.wnd_CaptionButtonGlyph))
        .setText(strings().lens_Commands)
        .padding         = metrics.btnIcon_Padding
        .toolTip         = Format.toString("% (Ctrl Space)", strings().lens_Commands)
        .preferredSize.x = Math.ceil(.itf.measureContent({}).x)
        .parent?.sendResizeEvent()
    }
}
