#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui

// Builds the real main window inside a headless surface of the shipped minimum size.
func testSetupMainWindow(host: *Testing.HeadlessHost)->*MainWindow
{
    host.setup(1100, 790)
    host.bindApplication(&g_App)
    registerAppStrings(&g_App.resources)

    let result = MainWindow.create(&host.root)
    host.surfaceWnd.view = result
    result.setPosition({0, 0, 1100, 790})
    result.applyLayout()
    return result
}

// The window is built in the reference language, whatever the language of the account.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    @assert(activeLanguage() == ReferenceLanguage)
    @assert(window.createButton.text() == "Create encrypted vault")
    @assert(window.language == ReferenceLanguage)
}

// Every shipped language holds the surface: nothing is arranged smaller than the text it
// has to show. This is what a caption or a wrapped paragraph sized by hand cannot promise.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()
    defer discard catch g_App.setLanguage(ReferenceLanguage)

    for &one in languages()
    {
        expect g_App.setLanguage(one.tag.toString())
        window.applyLayout()
        Testing.assertContentFits(window)
    }
}

// A language switch re-labels the buttons and re-measures them around the new wording.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()
    defer discard catch g_App.setLanguage(ReferenceLanguage)

    let englishWidth = window.unmountButton.position.width
    expect g_App.setLanguage("fr")
    window.applyLayout()

    @assert(window.unmountButton.text() == "Démonter")
    @assert(window.createButton.text() == "Créer le coffre chiffré")
    @assert(window.unmountButton.position.width != englishWidth)

    expect g_App.setLanguage(ReferenceLanguage)
    window.applyLayout()
    @assert(window.unmountButton.text() == "Unmount")
    @assert(window.unmountButton.position.width == englishWidth)
}

// Picking a language remembers it, and the system entry restores "follow the account".
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()
    defer discard catch g_App.setLanguage(ReferenceLanguage)

    // Entry zero follows the account; the languages come after it, in registration order,
    // and the window opens on the reference language rather than on the account.
    @assert(window.languageChoice.items.count == @countof(languages()) + 1)
    @assert(window.languageChoice.selectedIndex == 1)

    window.chooseLanguage(2)
    @assert(window.language == "fr")
    @assert(activeLanguage() == "fr")
    @assert(window.languageChoice.selectedIndex == 2)

    window.chooseLanguage(0)
    @assert(window.language.isEmpty())
    @assert(activeLanguage() == systemLanguage())
}

// The status line is named, not written, so it says the same thing in the new language.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()
    defer discard catch g_App.setLanguage(ReferenceLanguage)

    @assert(window.statusText() == "Ready — create a vault or choose one to mount.")

    window.statusDrive = "Z:"
    window.setStatus(.Mounted)
    @assert(Utf8.contains(window.statusText().toString(), "Z:"))

    expect g_App.setLanguage("fr")
    @assert(Utf8.startsWith(window.statusText().toString(), "Lecteur chiffré monté sur Z:"))
}
