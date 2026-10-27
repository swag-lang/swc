#global public
#global namespace Viewer

using Core, Gui

// A viewer-owned playback button for a dedicated command bar, showing the play mode in force.
//
// It opens an option sheet with the play mode and, for still pictures, the time per picture.
// The button borrows its document view and host callbacks. Its parent must be destroyed before
// or with that view. The host retains the playback policy.
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

        with let result = Wnd.create'PlaybackButton(parent, null, Math.Rectangle{0, 0, themeDropDownButtonWidth(metrics), themeActionButtonSize(metrics)})
        {
            .view              = view
            .playback          = playback
            .showSlideDuration = showSlideDuration
            .focusPolicy       = .Tab
            .wndFlags          |= .ActivatesOnKey
            .padding           = metrics.btnIcon_Padding
            .toolTip           = appStrings().ui_PlayMode
            .updateFlags(.CenterContent)
            .setArrowPosition(.RightUpward)
            .enable(playback.isAvailable())
            .refreshIcon()
            .sigPressed += func(button) { button.showOptions() }
        }

        return result
    }

    // Opens the playback options above this button; each choice applies the host policy at once.
    mtd showOptions()
    {
        let sheet = OptionSheet.View.create(me,
                                            func|button = me|(page)
                                            {
                                                button.playback.addOptionRows(page, button.view, button.showSlideDuration)
                                            },
                                            owner: .view)
        sheet.doModal(me, autoDestroy: true)
        .refreshIcon()
    }

    private mtd refreshIcon()
    {
        .button.setIcon(.theme().icon(playModeIcon(.playback.settings(.view).mode), themeActionIconSize(.themeMetrics())))
    }
}
