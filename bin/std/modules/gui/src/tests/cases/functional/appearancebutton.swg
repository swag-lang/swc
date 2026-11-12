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

// Any application with an appearance owner can expose its registered choices in a command menu.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 400)
    host.surface.flags = SurfaceFlags.StandardWindow
    host.surfaceWnd.create(&host.root, null)

    let button = AppearanceButton.create(&host.surface)
    let lens   = Lens.View.create(&host.root)
    button.addToLens(lens)

    let menu = lens.createCommandMenu()
    menu.updateState()
    Swag.require(menu.items.count == 1 and menu.items[0]!.name.raw == strings().lens_Application)
    let application = menu.items[0]!.popup
    Swag.require(application.items.count == 2)
    Swag.require(application.items[0]!.name.raw == strings().appearance_Theme)
    Swag.require(application.items[1]!.name.raw == strings().appearance_Language)
    let themes = application.items[0]!.popup
    themes.updateState()
    Swag.require(themes.items.count == 3 and themes.items[0]!.checked)

    host.root.sendCommandEvent(themes.items[1]!.id)
    Swag.require(button.appearanceTheme == .Light)
}

// The appearance menu starts from the application's previously selected theme.
#test
{
    for appearance in [AppearanceTheme.Light, .System]
    {
        var host: Testing.HeadlessHost
        host.setup(640, 400)
        host.surface.flags = SurfaceFlags.StandardWindow
        host.app.setAppearance(appearance)
        host.surfaceWnd.create(&host.root, null)

        let button = AppearanceButton.create(&host.surface)
        Swag.require(button.appearanceTheme == appearance)

        let lens = Lens.View.create(&host.root)
        button.addToLens(lens)
        lens.open(strings().appearance_Theme)
        let selected = appearance == .Light ? 1 : 2
        Swag.require(lens.results.sections[0]!.entries[selected].checked)
    }
}
