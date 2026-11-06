#global public
#global namespace Lens

using Core, Pixel

// Opens a command menu beside the application mark, or the lens from the ordinary caption door.
struct Launcher
{
    public using captionButton: Gui.CaptionButton     // Embedded caption-button behavior and presentation.
    command: String
    menuLens: *View?
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
    // Creates a named caption control that posts `command` to `owner`.
    //
    // The surface owns the button and the owner must outlive it. The control does not take
    // keyboard focus; applications can also route `Ctrl Space` to their lens.
    #[Swag.Discardable]
    func create(owner: *Wnd, command: WndId)->*Launcher => Launcher.createImpl(owner, command, null)

    // Creates an icon-only caption control beside the application mark.
    //
    // It opens a popup built solely from `menuLens`'s registered commands. The surface owns the
    // button; `owner` and `menuLens` must outlive it. Route `Ctrl Space` to the lens separately.
    #[Swag.Discardable]
    func createMenu(owner: *Wnd, menuLens: *View)->*Launcher => Launcher.createImpl(owner, "", menuLens)

    private func createImpl(owner: *Wnd, command: WndId, menuLens: *View?)->*Launcher
    {
        let surface     = unwrap owner.surface
        let parent      = assume cast(*SurfaceWnd, surface.wnd)
        with let result = Wnd.create'Launcher(parent)
        {
            .owner   = owner
            .command = command
            .menuLens = menuLens
            .captionButton.leading = menuLens != null
            .setForm(.RoundedRectangle)
            .focusPolicy = .None
            .sigPressed += func|result|(_)
            {
                if result.menuLens do
                    result.menuLens.openCommandMenu(&result.captionButton.button)
                else do
                    result.owner!.postCommandEvent(result.command)
            }
            .refreshLabel()
        }

        if menuLens do
            parent.registerLeadingCaptionButton(result)
        else do
            parent.registerCaptionButton(result)
        return result
    }

    private mtd refreshLabel()
    {
        let metrics = .themeMetrics()
        .captionButton.button.setIcon(.theme().icon(.menuLens ? ThemeIcons.MainMenu : .More, metrics.wnd_CaptionButtonGlyph))
        .setText(.menuLens ? "" : strings().lens_Commands)
        if not .menuLens do
            .setTextPosition(.Right)
        .padding         = metrics.btnIcon_Padding
        .toolTip         = .menuLens ? strings().lens_Commands : Format.toString("% (Ctrl Space)", strings().lens_Commands)
        .preferredSize.x = Math.ceil(.itf.measureContent({}).x)
        .parent?.sendResizeEvent()
    }
}
