#global public
#global namespace Viewer

using Core, Gui

// A viewer-owned playback-mode button for a dedicated command bar.
//
// The button borrows its document view and host callbacks. Its parent must be destroyed before
// or with that view. The host retains the playback policy; the button creates and owns its menu.
struct PlaybackButton
{
    public using button: IconButton     // Standard icon-button layout and input behavior.

    late view:         *Wnd
    playback:          PlaybackApi
    showSlideDuration: bool
}

private impl IWnd for PlaybackButton
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        .refreshIcon()
        .button.IWnd.onPaint(evt)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .toolTip = appStrings().ui_PlayMode
        .button.IWnd.onNotifyEvent(evt)
    }
}

impl PlaybackButton
{
    // Creates a playback button under the viewer's command group, optionally offering still-picture duration.
    //
    // `view` and `playback` remain borrowed until the parent destroys the button. The caller owns
    // its docking and spacing. A host without playback callbacks produces a disabled button.
    func create(parent: *Wnd, view: *Wnd, playback: PlaybackApi, showSlideDuration = false)->*PlaybackButton
    {
        let metrics = parent.themeMetrics()
        let result  = Wnd.create'PlaybackButton(parent, null, {0, 0, themeDropDownButtonWidth(metrics), themeActionButtonSize(metrics)})
        result.view              = view
        result.playback          = playback
        result.showSlideDuration = showSlideDuration
        result.focusPolicy       = .Tab
        result.wndFlags          |= .ActivatesOnKey
        result.padding           = metrics.btnIcon_Padding
        result.updateFlags(.CenterContent)
        result.setArrowPosition(.RightUpward)
        result.toolTip = appStrings().ui_PlayMode
        result.enable(playback.isAvailable())
        result.refreshIcon()
        result.sigPressed += func(button) { (cast(*PlaybackButton) button).showMenu() }
        return result
    }

    // Builds the current playback menu; the caller owns and must destroy it.
    mtd createMenu()->*MenuCtrl
    {
        let menu = MenuCtrl.createPopup(me, owner: .view)
        .playback.appendMenuItems(menu, .view, .showSlideDuration)
        return menu
    }

    // Opens the menu above this button and applies the selected host policy.
    mtd showMenu()
    {
        let menu   = .createMenu()
        let chosen = menu.doModal(me, autoDestroy: true)
        if chosen do
            discard .playback.applyMenuChoice(.view, chosen!, .showSlideDuration)
        .refreshIcon()
    }

    private mtd refreshIcon()
    {
        .button.setIcon(.theme().icon(playModeIcon(.playback.settings(.view).mode), themeActionIconSize(.themeMetrics())))
    }
}
