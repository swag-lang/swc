#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// A staged step waiting for a menu where the button opens a sheet fails the step instead of
// leaving the sheet running forever.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 240)
    host.surface.flags = SurfaceFlags.StandardWindow
    host.surfaceWnd.create(&host.root, null)
    host.surfaceWnd.sendResizeEvent()
    let button = AppearanceButton.create(&host.surface)
    host.surfaceWnd.sendResizeEvent()

    let systemGap      = host.theme.metrics.wnd_CaptionButtonGap
    let actionGap      = host.theme.metrics.wnd_CaptionActionGap
    let closeButton    = unwrap host.surfaceWnd.closeBtn
    let maximizeButton = unwrap host.surfaceWnd.maximizeBtn
    let minimizeButton = unwrap host.surfaceWnd.minimizeBtn
    Swag.require(Math.abs(maximizeButton.position.right() + systemGap - closeButton.position.x) < 0.5)
    Swag.require(Math.abs(minimizeButton.position.right() + systemGap - maximizeButton.position.x) < 0.5)
    Swag.require(Math.abs(button.position.right() + actionGap - minimizeButton.position.x) < 0.5)

    host.openPopupSubMenuWhenShown(strings().appearance_Language, maxFrames: 2)
    host.clickWnd(button)
    Swag.require(not host.autoHandled and not host.autoFailure.isEmpty())
    Swag.require(host.capturedOptionSheet() == null)
}

// The appearance is found through the lens like any other command: the themes and the languages
// as rows applying their choice, the one in force checked, and About when it has a listener.
#test
{
    var themeChanges, aboutRequests: u32
    var host: Testing.HeadlessHost
    host.setup(640, 400)
    host.surface.flags = SurfaceFlags.StandardWindow
    host.surfaceWnd.create(&host.root, null)
    host.surfaceWnd.sendResizeEvent()

    let button = AppearanceButton.create(&host.surface)
    button.sigThemeChanged   += func|count = &themeChanges|(_) { count[] += 1 }
    button.sigAboutRequested += func|count = &aboutRequests|(_) { count[] += 1 }

    let lens = Lens.View.create(&host.root)
    button.addToLens(lens)

    // A query naming the group lists all of it, with the choice in force checked.
    lens.open(strings().appearance_Theme)
    let themes = unwrap lens.results.sections[0]
    Swag.require(themes.label == strings().appearance_Theme and themes.entries.count == 3)
    Swag.require(themes.entries[0].checked and not themes.entries[1].checked)

    lens.setQuery(strings().appearance_Light)
    Swag.require(lens.chosenEntry()!.title == strings().appearance_Light)
    lens.runChosen()
    Swag.require(button.appearanceTheme == .Light and themeChanges == 1)

    lens.open(strings().appearance_About)
    Swag.require(lens.chosenEntry()!.title == strings().appearance_About)
    lens.runChosen()
    Swag.require(aboutRequests == 1)
}
