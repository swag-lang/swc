#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// Home and the vault list offer Options as a page link. The command remains searchable in both
// shipped languages, and the Options page keeps its quiet link back to the vaults.
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
        Swag.require(window.list.options.isLocallyVisible() and window.list.options.isEnabled())
        Swag.require(window.list.options.text() == appStrings().ui_OptionsLink)
        window.lens.open()
        Swag.require(lensHasEntry(window, appStrings().cmd_Options))
        window.lens.close()
        window.lens.open("options")
        Swag.require(lensHasEntry(window, appStrings().cmd_Options))
        window.lens.close()
        host.clickWnd(window.list.options)
        Swag.require(window.page == .Options and window.optionsPage.isLocallyVisible())
        Swag.require(not window.list.scroll.isLocallyVisible())
        host.clickWnd(window.optionsPage.head.back)
        Swag.require(window.page == .List and window.list.options.isLocallyVisible())
    }
}
