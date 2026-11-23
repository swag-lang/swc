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
        let forward = window.list.options.surfaceRect()
        host.clickWnd(window.list.options)
        Swag.require(window.page == .Options and window.optionsPage.isLocallyVisible())
        Swag.require(not window.list.scroll.isLocallyVisible())
        let back = window.optionsPage.head.back.surfaceRect()
        Swag.require(forward.y == back.y and forward.height == back.height)
        Swag.require(Math.abs(forward.right() + back.x - 2 * window.surfaceRect().horzCenter()) <= 1)
        host.clickWnd(window.optionsPage.head.back)
        Swag.require(window.page == .List and window.list.options.isLocallyVisible())
    }
}

// A scrolling list mirrors the return link even when its scrollbar takes part of the view.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, 1.25, width: 1280, height: 800)
    fillPictureList(window)
    for index in 8 do
        window.vaults.add(KnownVault{Format.toString("/vaults/extra-%", index), "", false})
    window.refreshVaults()
    Swag.require(window.list.position.width < window.clientRect().width)

    let forward = window.list.options.surfaceRect()
    host.clickWnd(window.list.options)
    Swag.require(window.page == .Options)
    let back = window.optionsPage.head.back.surfaceRect()
    Swag.require(forward.y == back.y and forward.height == back.height)
    Swag.require(Math.abs(forward.right() + back.x - 2 * window.surfaceRect().horzCenter()) <= 1)
}
