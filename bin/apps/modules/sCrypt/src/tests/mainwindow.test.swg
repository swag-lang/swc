#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui

// Builds the real main window inside a headless surface of the shipped minimum size.
func testSetupMainWindow(host: *Testing.HeadlessHost)->*MainWindow
{
    host.setup(1100, 790)
    host.bindApplication(&g_App)

    // The window resolves its application through its surface, so that is the one a language
    // switch travels through and the one that has to be able to find the translations. The
    // module global gets them too, because the code under test reads `g_App` directly.
    registerAppStrings(&g_App.resources)
    registerAppStrings(&host.app.resources)

    // Built on the surface root, the way the application builds it: the window installs itself
    // as the view of its surface, which destroys whatever view was there before.
    let result = MainWindow.create(&host.surfaceWnd)
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
        host.notify(.LanguageChanged)
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

    // Entry zero follows the account, so the registered languages start at one: one is the
    // reference language and two is French. Going through the picker is what the user does, and
    // it is what carries the change all the way to the labels.
    let englishWidth = window.unmountButton.position.width
    window.chooseLanguage(2)
    host.notify(.LanguageChanged)

    @assert(window.unmountButton.text() == "Démonter")
    @assert(window.createButton.text() == "Créer le coffre chiffré")
    @assert(window.unmountButton.position.width != englishWidth)

    window.chooseLanguage(1)
    host.notify(.LanguageChanged)
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
    host.notify(.LanguageChanged)
    @assert(window.language == "fr")
    @assert(activeLanguage() == "fr")
    @assert(window.languageChoice.selectedIndex == 2)

    window.chooseLanguage(0)
    @assert(window.language.isEmpty())
    @assert(activeLanguage() == systemLanguage())
}

// The whole window is reachable from the keyboard, in the order it reads.
//
// Both cards are built with their action bar docked under a form that fills the space left over,
// so this also pins that the traversal follows the arranged rectangles rather than the order the
// windows were created in.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    let order = Gui.FocusOrder.collect(window)

    // A button that cannot work is down, and the keyboard does not stop on it: on a form with
    // nothing filled in, the three actions of the window are out of the ring.
    @assert(order.stops.count == 11)
    @assert(order.stops[0] == cast(*Wnd) window.createPath)
    @assert(order.stops[6] == cast(*Wnd) window.mountPath)

    // Live, each action takes its place after the card it answers for.
    window.createButton.enable(true)
    window.mountButton.enable(true)
    window.unmountButton.enable(true)

    let full = Gui.FocusOrder.collect(window)
    @assert(full.stops.count == 14)
    @assert(full.stops[0] == cast(*Wnd) window.createPath)
    @assert(full.stops[1] == cast(*Wnd) window.browseCreate)
    @assert(full.stops[2] == cast(*Wnd) window.createSize)
    @assert(full.stops[3] == cast(*Wnd) window.createUnit)
    @assert(full.stops[4] == cast(*Wnd) window.createPassword)
    @assert(full.stops[5] == cast(*Wnd) window.confirmPassword)
    @assert(full.stops[6] == cast(*Wnd) window.createButton)
    @assert(full.stops[7] == cast(*Wnd) window.mountPath)
    @assert(full.stops[8] == cast(*Wnd) window.browseMount)
    @assert(full.stops[9] == cast(*Wnd) window.mountPassword)
    @assert(full.stops[10] == cast(*Wnd) window.drive)
    @assert(full.stops[11] == cast(*Wnd) window.mountButton)
    @assert(full.stops[12] == cast(*Wnd) window.unmountButton)
    @assert(full.stops[13] == cast(*Wnd) window.languageChoice)

    // It opens on the first field, and Tab moves on from there.
    @assert(window.createPath.hasFocus())
    host.keyPress(Input.Key.Tab)
    @assert(window.browseCreate.hasFocus())
}

// A form that goes down while it holds the keyboard hands it to what is still live.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    window.createPassword.setFocus()
    @assert(window.createPassword.hasFocus())

    // What a creation does: both forms go down and the create button stays live, because during a
    // creation it is what stops it. The keyboard has to follow, or the next key reaches a control
    // the user can no longer act on.
    window.setState(.Creating)
    @assert(window.createButton.hasFocus())
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

// A failure says its sentence in the active language, not the diagnostic the layer wrote.
//
// The volume layer reports an ErrorKind and an English diagnostic for whoever reads a
// report; what the reader is shown comes from the string table.
#test
{
    var host: Testing.HeadlessHost
    discard testSetupMainWindow(&host)
    defer host.shutdown()
    defer discard catch g_App.setLanguage(ReferenceLanguage)

    func messageFor(kind: ErrorKind)->string
    {
        catch failWith("an English diagnostic nobody reads", kind) as err
        return caughtMessage(err)
    }

    // The English diagnostic never reaches the reader, in either language.
    @assert(messageFor(.PasswordOrDamaged) == "The password is incorrect or the container is damaged.")
    @assert(messageFor(.Corrupted) == "The container is damaged.")
    @assert(messageFor(.PasswordRequired) == "A password is required.")
    @assert(messageFor(.Canceled) == "The operation stopped.")

    // Every way a container can refuse to open answers the same sentence: telling a wrong
    // password from a damaged container is exactly what the format refuses to do.
    @assert(messageFor(.PasswordOrDamaged) != messageFor(.Corrupted))

    expect g_App.setLanguage("fr")
    @assert(messageFor(.PasswordOrDamaged) == "Le mot de passe est incorrect ou le conteneur est endommagé.")
    @assert(messageFor(.PasswordRequired) == appStrings().msg_PasswordRequired)
    @assert(messageFor(.DiskFull) == appStrings().msg_ErrDiskFull)

    // A kind that means nothing to a reader reads as the generic damaged-container wording.
    @assert(messageFor(.DirectoryNotEmpty) == appStrings().msg_ErrDamaged)
    @assert(messageFor(.NotDirectory) == appStrings().msg_ErrDamaged)
}
