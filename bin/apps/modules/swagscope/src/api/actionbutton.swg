#global public
#global namespace Viewer

using Gui, Pixel

// Creates a square command button showing `icon`, sized like every action of a command bar.
func createActionButton(parent: *Wnd, icon: ThemeIcons, flags = IconButtonFlags.None)->*IconButton
{
    let metrics = parent.themeMetrics()
    let size    = themeActionButtonSize(metrics)
    return IconButton.create(parent, parent.theme().icon(icon, themeActionIconSize(metrics)), Math.Rectangle{0, 0, size, size}, flags: flags)
}

// Creates a command button showing `icon` with room for the arrow of the menu it opens.
func createActionDropDown(parent: *Wnd, icon: ThemeIcons)->*IconButton
{
    let metrics = parent.themeMetrics()
    let width   = themeDropDownButtonWidth(metrics)
    let height  = themeActionButtonSize(metrics)
    return IconButton.create(parent, parent.theme().icon(icon, themeActionIconSize(metrics)), Math.Rectangle{0, 0, width, height}, flags: .CenterContent)
}

// Creates the button that opens the option sheet of a viewer, its arrow pointing to where it opens.
func createOptionsButton(parent: *Wnd)->*IconButton
{
    with let result = createActionDropDown(parent, .Settings)
    {
        .toolTip = appStrings().ui_Options
        .setArrowPosition(.RightUpward)
        .setTextPosition(.Right)
    }

    return result
}

// Writes `badge` beside the icon of an options button, or nothing when it is empty.
//
// A badge reports a setting the reader would want to see without opening the sheet, such as a
// playback rate that is not the normal one. The button widens to hold it.
func setOptionsBadge(button: *IconButton, badge: string)
{
    if button.name.raw == badge do
        return
    button.setText(badge)

    let metrics = button.themeMetrics()
    var width   = themeDropDownButtonWidth(metrics)
    if badge.count do
        width += Painter.measureString(badge, unwrap button.font().regular).width + metrics.btnIcon_SpacingTextH + 2
    button.resize(Math.ceil(width), button.position.height)
    button.parent?.applyLayout()
}
