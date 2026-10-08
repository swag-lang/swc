#global public
#global namespace Viewer

using Gui

// Creates a square command button showing `icon`, sized like every action of a command bar.
func createActionButton(parent: *Wnd, icon: ThemeIcons, flags = IconButtonFlags.None)->*IconButton
{
    let metrics = parent.themeMetrics()
    let size    = themeActionButtonSize(metrics)
    return IconButton.create(parent, parent.theme().icon(icon, themeActionIconSize(metrics)), {0, 0, size, size}, flags: flags)
}

// Creates a command button showing `icon` with room for the arrow of the menu it opens.
func createActionDropDown(parent: *Wnd, icon: ThemeIcons)->*IconButton
{
    let metrics = parent.themeMetrics()
    let width   = themeDropDownButtonWidth(metrics)
    let height  = themeActionButtonSize(metrics)
    return IconButton.create(parent, parent.theme().icon(icon, themeActionIconSize(metrics)), {0, 0, width, height}, flags: .CenterContent)
}
