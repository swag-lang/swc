#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// Home and the vault list offer Options directly. The icon runs the same command as the lens
// and stays out of keyboard focus; Options remains searchable in both shipped languages.
#test
{
    defer discard catch g_App.setLanguage(ReferenceLanguage)
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    for tag in [ReferenceLanguage, "fr"]
    {
        expect g_App.setLanguage(tag)
        host.notify(.LanguageChanged)
        window.showPage(.List, animate: false)
        Swag.require(window.optionsButton.isLocallyVisible() and window.optionsButton.isEnabled())
        Swag.require(window.optionsButton.focusPolicy == .None)
        Swag.require(window.optionsButton.toolTip == appStrings().cmd_Options)
        window.lens.open()
        Swag.require(lensHasEntry(window, appStrings().cmd_Options))
        window.lens.close()
        window.lens.open("options")
        Swag.require(lensHasEntry(window, appStrings().cmd_Options))
        window.lens.close()
        host.clickWnd(window.optionsButton)
        Swag.require(window.page == .Options and window.optionsPage.isLocallyVisible())
        Swag.require(not window.optionsButton.isLocallyVisible())
        host.clickWnd(window.optionsPage.head.back)
        Swag.require(window.page == .List and window.optionsButton.isLocallyVisible())
    }
}
