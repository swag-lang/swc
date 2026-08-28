#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui

// Builds the real main window inside a headless surface of the shipped minimum size.
func testSetupMainWindow(host: *Testing.HeadlessHost)->*MainWindow
{
    host.setup(cast(f32) MainWindow.WindowWidth, cast(f32) MainWindow.WindowHeight)
    host.bindApplication(&g_App)

    // The window resolves its application through its surface, so that is the one a language
    // switch travels through and the one that has to be able to find the translations. The
    // module global gets them too, because the code under test reads `g_App` directly.
    registerAppStrings(&g_App.resources)
    registerAppStrings(&host.app.resources)

    // Built on the surface root, the way the application builds it: the window installs itself
    // as the view of its surface, which destroys whatever view was there before.
    let result = MainWindow.create(&host.surfaceWnd)

    // The shipped surface draws its own caption and border, and its view sits inside them, so the
    // window is that much smaller than the size passed to `createSurface`. The host builds no
    // chrome at all, so a window given the whole rectangle is measured taller than the one that
    // ships — and 43 logical pixels is exactly the room the last help paragraph of a card needs.
    // A card clipped in the real window went on passing the containment test below for that
    // reason, in every language, for as long as the test sized the window itself.
    let metrics = host.theme.metrics
    let border  = metrics.wnd_BorderSize
    let caption = Math.max(metrics.wnd_BigCaptionCY, border)
    result.setPosition({0, 0, cast(f32) MainWindow.WindowWidth - 2 * border, cast(f32) MainWindow.WindowHeight - caption - border})
    result.applyLayout()
    return result
}

// Writes and reads the state event at the same boundary the application state file uses.
func saveMainWindowState(window: *MainWindow)->String
{
    var result:     ConcatBuffer
    var encoder:    Serialization.Encoder'Serialization.Write.TagBin
    var serializer: Serialization.Serializer
    expect serializer.startWrite(&encoder, &result)
    expect serializer.beginSection(.Unordered)
    expect window.serializeState(&serializer)
    expect serializer.endSection()
    expect serializer.end()
    return result.toString()
}

func loadMainWindowState(window: *MainWindow, bytes: const [..] u8)
{
    var decoder:    Serialization.Decoder'Serialization.Read.TagBin
    var serializer: Serialization.Serializer
    expect serializer.startRead(&decoder, bytes)
    expect serializer.beginSection(.Unordered)
    expect window.serializeState(&serializer)
    expect serializer.endSection()
    expect serializer.end()
}

func containsStateBytes(bytes, needle: const [..] u8)->bool
{
    if !@countof(needle) or @countof(needle) > @countof(bytes) do
        return false
    for offset in @countof(bytes) - @countof(needle) + 1
    {
        if @memcmp(@dataof(bytes) + offset, @dataof(needle), @countof(needle)) == 0 do
            return true
    }

    return false
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
    @assert(window.appearanceButton.parent == &host.surfaceWnd)
    @assert(window.appearanceButton.focusPolicy == .None)

    window.themeIndex = cast(u32) AppearanceTheme.Dark
    window.applyTheme()
    @assert(window.appearanceButton.appearanceTheme == .Dark and host.theme.colors.bk == ThemeColors.darkPalette().ground)
    window.themeIndex = cast(u32) AppearanceTheme.Light
    window.applyTheme()
    @assert(window.appearanceButton.appearanceTheme == .Light and host.theme.colors.bk == ThemeColors.lightPalette().ground)
    window.themeIndex = cast(u32) AppearanceTheme.SwagDark
    window.applyTheme()
    @assert(window.appearanceButton.appearanceTheme == .SwagDark and host.theme.colors.bk == ThemeColors.swagDarkPalette().ground)
}

// Privacy is the default and keeps every vault path out of persistent state.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    @assert(window.privacyMode)
    @assert(window.privacyModeControl.isChecked())
    @assert(!window.mountedDrives.startupEnabled)

    window.mountSettings.path = String.from("C:\\private\\unlisted")
    window.startupVaults.add({String.from("C:\\private\\startup"), String.from("mount-x"), true, false})
    window.fileDlgState.currentFolder = String.from("C:\\private\\browse-private")
    var state = saveMainWindowState(window)
    @assert(!containsStateBytes(state.toSlice(), @mkslice(cast(const [*] u8) @dataof("unlisted"), 8)))
    @assert(!containsStateBytes(state.toSlice(), @mkslice(cast(const [*] u8) @dataof("startup"), 7)))
    @assert(!containsStateBytes(state.toSlice(), @mkslice(cast(const [*] u8) @dataof("browse-private"), 14)))

    window.clearPrivateState()
    @assert(window.mountSettings.path.isEmpty())
    @assert(window.startupVaults.isEmpty())
}

// The caption appearance action reaches the standard application about dialog.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    @assert(!window.appearanceButton.sigAboutRequested.isEmpty())
    host.clickModalButtonWhenShown(Dialog.BtnCancel)
    window.showAbout()
    host.pump()

    @assert(host.autoHandled)
    @assert(host.openedSurfaceCount() == 0)
}

// A card's form has to end inside the card, in every language.
//
// A card is exactly as tall as the page it fills and no taller: a form that grows past its body
// is not pushed down, it is cut off at the bottom edge. That is what a longer translation does to
// the last help paragraph of a card, and neither the form nor the body reports it — the form is
// sized by its own measure, so it always "fits" itself, and the body answers for no content size
// at all.
//
// Bring the card's page up before measuring it. A tab that is not on show is not arranged, so its
// body answers a negative height and the comparison passes on a card nobody sized.
func assertFormEndsInsideCard(card: const *VaultCard, tolerance = 0.5'f32)
{
    let room   = card.body.clientRect().height
    let needed = card.form.position.bottom()
    if needed > room + tolerance
    {
        Console.println("form does not end inside its card: needs ", needed, ", body holds ", room)
        @assert(false)
    }
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

        window.showTab(0)
        assertFormEndsInsideCard(&window.createCard)

        window.showTab(1)
        assertFormEndsInsideCard(&window.mountCard)

        window.showTab(3)
        assertFormEndsInsideCard(&window.optionsCard)
    }

    window.showTab(0)
}

// A language switch re-labels the complete surface.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()
    defer discard catch g_App.setLanguage(ReferenceLanguage)

    // Entry zero follows the account, so the registered languages start at one: one is the
    // reference language and two is French. Going through the picker is what the user does, and
    // it is what carries the change all the way to the labels.
    let unmount = window.mountedDrives.unmountButton
    expect window.appearanceButton.setAppearanceLanguage("fr", notify: true)
    host.notify(.LanguageChanged)

    @assert(unmount.text() == "Démonter")
    @assert(window.createButton.text() == "Créer le coffre chiffré")
    @assert(window.createKeyFiles.generate.toolTip == "Créer un fichier clé aléatoire")

    // The third card follows too, headings and all.
    @assert(window.mountedDrives.list.header.itemAt(cast(u32) MountedColumn.Startup).name.raw == "AU DÉMARRAGE")
    @assert(window.mountedDrives.list.header.itemAt(cast(u32) MountedColumn.Size).name.raw == "TAILLE")
    @assert(window.mountedDrives.list.header.itemAt(cast(u32) MountedColumn.Available).name.raw == "DISPONIBLE")
    @assert(window.mountedDrives.empty.text() == "Aucun lecteur monté.")

    expect window.appearanceButton.setAppearanceLanguage(ReferenceLanguage, notify: true)
    host.notify(.LanguageChanged)
    @assert(unmount.text() == "Unmount")
}

// Picking a language remembers it, and the system entry restores "follow the account".
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()
    defer discard catch g_App.setLanguage(ReferenceLanguage)

    // The window opens on the reference language rather than on the account.
    @assert(window.appearanceButton.language == ReferenceLanguage)

    expect window.appearanceButton.setAppearanceLanguage("fr", notify: true)
    host.notify(.LanguageChanged)
    @assert(window.language == "fr")
    @assert(activeLanguage() == "fr")
    @assert(window.appearanceButton.language == "fr")

    expect window.appearanceButton.setAppearanceLanguage("", notify: true)
    @assert(window.language.isEmpty())
    @assert(activeLanguage() == systemLanguage())
}

// The last successful mount prepares the next open-vault form without retaining a credential.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    window.privacyMode = false
    window.applyPrivacyControl()

    let drive = window.selectedMountPoint()
    @assert(!drive.isEmpty())

    window.operation.path     = String.from("C:\\vaults\\remembered")
    window.operation.mount    = drive
    window.operation.readOnly = true
    window.rememberMountedDrive()

    // Put unmistakable bytes in the password storage. Persistent state must never observe them.
    let secret = "not a setting"
    @memcpy(&window.mountPassword.storage[0], @dataof(secret), @countof(secret))
    window.mountPassword.byteCount = @countof(secret)

    var state       = saveMainWindowState(window)
    let secretBytes = @mkslice(cast(const [*] u8) @dataof(secret), @countof(secret))
    @assert(!containsStateBytes(state.toSlice(), secretBytes))

    window.mountKeyFiles.paths.add(String.from("C:\\private\\access.key"))
    state = saveMainWindowState(window)
    @assert(!containsStateBytes(state.toSlice(), @mkslice(cast(const [*] u8) @dataof("access.key"), 10)))

    window.mountSettings = {}
    window.mountPath.setText("")
    window.readOnly.setState(.Unchecked)
    window.mountPassword.clear()
    var noKeyFiles: Array'String
    window.mountKeyFiles.setPaths(noKeyFiles.toSlice())
    loadMainWindowState(window, state.toSlice())

    @assert(window.mountPath.text() == "C:\\vaults\\remembered")
    @assert(window.selectedMountPoint() == drive)
    @assert(window.readOnly.isChecked())
    @assert(window.mountPassword.isEmpty())
    @assert(window.mountKeyFiles.paths.isEmpty())
}

// Automatic-unmount choices are explicit persistent policy, and the timeout is only actionable
// while inactivity handling is enabled.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    @assert(window.unmountOnLock.isChecked())
    @assert(window.unmountOnSuspend.isChecked())
    @assert(!window.unmountOnIdle.isChecked())
    @assert(!window.idleTimeout.isEnabled())

    window.unmountOnLock.toggle()
    window.unmountOnIdle.toggle()
    window.idleTimeout.setSelectedIndex(2)
    window.readAutoUnmountControls()
    var state = saveMainWindowState(window)

    window.autoUnmount = {}
    window.applyAutoUnmountControls()
    loadMainWindowState(window, state.toSlice())

    @assert(!window.autoUnmount.onSessionLock)
    @assert(window.autoUnmount.onSuspend)
    @assert(window.autoUnmount.onIdle)
    @assert(window.autoUnmount.idleMinutes == 30)
    @assert(window.idleTimeout.isEnabled())
}

// A configured event closes protected drives only. An unprotected container has no key to wipe
// and remains mounted, while startup marks remain policy for the next application start.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    window.mountedDrives.drives.add({null, String.from("C:\\protected"), String.from("mount-x"), String.from("X:"), true, false, true, 0, 0})
    window.mountedDrives.drives.add({null, String.from("C:\\open"), String.from("mount-y"), String.from("Y:"), false, false, false, 0, 0})
    window.mountedDrives.refresh()
    window.handleAutoUnmount(.SessionLock)

    @assert(window.mountedDrives.drives.count == 1)
    @assert(window.mountedDrives.drives[0].path == "C:\\open")
    @assert(window.statusMessage == .AutoUnmounted)

    window.autoUnmount.onSessionLock = false
    window.mountedDrives.drives.add({null, String.from("C:\\second"), String.from("mount-z"), String.from("Z:"), true, false, false, 0, 0})
    window.handleAutoUnmount(.SessionLock)
    @assert(window.mountedDrives.drives.count == 2)
}

// The page on show is reachable from the keyboard, in the order it reads, and it is the only
// page in the ring.
//
// The language picker reads first in the header, followed by the strip and the active page. A
// card is built with its action bar docked under a form that fills the space left over, so this
// also pins that traversal follows the arranged rectangles rather than creation order.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    // It opens on the first field to fill in and not on the strip, even though the strip is what
    // reads first, and Tab moves on from there.
    @assert(window.createPath.hasFocus())
    host.keyPress(Input.Key.Tab)
    @assert(window.browseCreate.hasFocus())

    let order = Gui.FocusOrder.collect(window)

    // A button that cannot work is down, and the keyboard does not stop on it: on a form with
    // nothing filled in, the action of the create page is out of the ring. So is every control
    // of the two pages that are not on show.
    @assert(order.stops.count == 9)
    @assert(order.stops[0] == cast(*Wnd) window.tabs)
    @assert(order.stops[1] == cast(*Wnd) window.createPath)

    // Live, each action takes its place after the card it answers for, and the dominant one
    // comes last on its card because the bar stacks from its right edge.
    window.createButton.enable(true)
    window.mountButton.enable(true)
    window.resizeButton.enable(true)
    window.passwordButton.enable(true)
    window.keyFilesButton.enable(true)

    let full = Gui.FocusOrder.collect(window)
    @assert(full.stops.count == 10)
    @assert(full.stops[0] == cast(*Wnd) window.tabs)
    @assert(full.stops[1] == cast(*Wnd) window.createPath)
    @assert(full.stops[2] == cast(*Wnd) window.browseCreate)
    @assert(full.stops[3] == cast(*Wnd) window.createSize)
    @assert(full.stops[4] == cast(*Wnd) window.createUnit)
    @assert(full.stops[5] == cast(*Wnd) window.createPassword)
    @assert(full.stops[6] == cast(*Wnd) window.confirmPassword)
    @assert(full.stops[7] == cast(*Wnd) window.createKeyFiles.add)
    @assert(full.stops[8] == cast(*Wnd) window.createKeyFiles.generate)
    @assert(full.stops[9] == cast(*Wnd) window.createButton)

    // Bringing up another page swaps the whole middle of the ring for that page's controls, and
    // the dominant action still comes last on its card because the bar stacks from its right edge.
    window.showTab(1)
    let opened = Gui.FocusOrder.collect(window)
    @assert(opened.stops.count == 11)
    @assert(opened.stops[0] == cast(*Wnd) window.tabs)
    @assert(opened.stops[1] == cast(*Wnd) window.mountPath)
    @assert(opened.stops[2] == cast(*Wnd) window.browseMount)
    @assert(opened.stops[3] == cast(*Wnd) window.mountPassword)
    @assert(opened.stops[4] == cast(*Wnd) window.mountKeyFiles.add)
    @assert(!window.mountKeyFiles.generate.isVisible())
    @assert(opened.stops[5] == cast(*Wnd) window.drive)
    @assert(opened.stops[6] == cast(*Wnd) window.readOnly)
    @assert(opened.stops[7] == cast(*Wnd) window.keyFilesButton)
    @assert(opened.stops[8] == cast(*Wnd) window.passwordButton)
    @assert(opened.stops[9] == cast(*Wnd) window.resizeButton)
    @assert(opened.stops[10] == cast(*Wnd) window.mountButton)

    window.showTab(3)
    let options = Gui.FocusOrder.collect(window)
    @assert(options.stops[0] == cast(*Wnd) window.tabs)
    @assert(options.stops[1] == cast(*Wnd) window.privacyModeControl)
    @assert(options.stops[2] == cast(*Wnd) window.unmountOnLock)
    @assert(options.stops[3] == cast(*Wnd) window.unmountOnSuspend)
    @assert(options.stops[4] == cast(*Wnd) window.unmountOnIdle)

    window.showTab(0)
}

// The file box is opened, backed out of, and left behind without the keyboard going missing.
//
// This is the whole browse gesture done from the keyboard: Tab to the action, Space to open the
// box, Escape to leave it, and the form resumes at the control the box was opened from.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    // Walk to the browse action of the mount card the way the reader does: bring its page up,
    // then Tab from the field the page opens on to the action beside it.
    window.showTab(1)
    window.mountPath.setFocus()
    @assert(window.mountPath.hasFocus())
    host.keyPress(Input.Key.Tab)
    @assert(window.browseMount.hasFocus())

    // The box runs a nested loop, so the way out is armed before it opens. Escape has to reach
    // the cancel action of the box from the file list the box opens the keyboard on. A box that
    // does not answer it is closed by hand after a few frames, so this fails on its assertion
    // rather than pumping frames until the runner gives up on it.
    var frames = 0's32
    var forced: bool
    host.app.sigFrame += func|host = &host, frames = &frames, forced = &forced|(app)
    {
        if !host.openedSurfaceCount() do
            return

        frames[] += 1
        if frames[] == 1 do
            host.keyPress(Input.Key.Escape)
        elif frames[] > 30
        {
            forced[] = true
            app.exitModal(Gui.Dialog.BtnCancel)
        }
    }

    host.keyPress(Input.Key.Space)

    // A zero frame count means the browse action never opened the box; `forced` means the box
    // opened and Escape was not what closed it.
    @assert(frames != 0)
    @assert(!forced)
    @assert(host.openedSurfaceCount() == 0)

    // Nothing was chosen, and the keyboard is back where it was.
    @assert(@countof(window.mountPath.text()) == 0)
    @assert(window.browseMount.hasFocus())

    host.keyPress(Input.Key.Tab)
    @assert(window.mountPassword.hasFocus())
    host.keyPress(Input.Key.Tab, Input.KeyModifiers.Shift)
    @assert(window.browseMount.hasFocus())
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

    @assert(window.statusText() == "Ready — create a vault or choose one to open.")

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

    func messageFor(kind: ErrorKind)->String
    {
        catch failWith("an English diagnostic nobody reads", kind) as err
        return caughtMessage(err)
    }

    // The English diagnostic never reaches the reader, in either language.
    @assert(messageFor(.PasswordOrDamaged) == "The password or key files are incorrect, or the container is damaged.")
    @assert(messageFor(.Corrupted) == "The container is damaged.")
    @assert(messageFor(.PasswordRequired) == "A password is required.")
    @assert(messageFor(.Canceled) == "The operation stopped.")

    // Every way a container can refuse to open answers the same sentence: telling wrong access
    // from a damaged container is exactly what the format refuses to do.
    @assert(messageFor(.PasswordOrDamaged) != messageFor(.Corrupted))

    expect g_App.setLanguage("fr")
    @assert(messageFor(.PasswordOrDamaged) == "Le mot de passe ou les fichiers clés sont incorrects, ou le conteneur est endommagé.")
    @assert(messageFor(.PasswordRequired) == appStrings().msg_PasswordRequired)
    @assert(messageFor(.DiskFull) == appStrings().msg_ErrDiskFull)

    // A kind that means nothing to a reader reads as the generic damaged-container wording.
    @assert(messageFor(.DirectoryNotEmpty) == appStrings().msg_ErrDamaged)
    @assert(messageFor(.NotDirectory) == appStrings().msg_ErrDamaged)
}

// A form with no password in it is a form that can act: an empty password is a vault that
// opens without one, not a field left blank.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    @assert(!window.canCreate())
    window.createPath.setText("C:\\open")
    @assert(window.canCreate())
    @assert(window.createButton.isEnabled())

    // The two actions that change a container need the file and nothing else: the password they
    // act on is the one their own box asks for, never what this card happens to be holding.
    @assert(!window.canModifyVault())
    window.mountPath.setText("C:\\open")
    @assert(window.canModifyVault())
    @assert(window.canMount())
    @assert(window.passwordButton.isEnabled())
    @assert(window.resizeButton.isEnabled())
}

// Opens `dialog`, backs straight out of it, and reports that the box really came up.
//
// Nothing here answers the form: what has to run is the box itself, because that is what measures
// the surface against the fields it was given.
func openAndDismiss(host: *Testing.HeadlessHost, dialog: *FormDlg)
{
    host.clickModalButtonWhenShown(Dialog.BtnCancel)
    @assert(dialog.doModal() == Dialog.BtnCancel)
    @assert(host.autoHandled)
}

// Boxes contain only the change being made. Current password and key files stay on the open card,
// where mounting, resizing, and both access changes read the same input once.
#test
{
    var host: Testing.HeadlessHost
    discard testSetupMainWindow(&host)
    defer host.shutdown()

    let texts = appStrings()

    var options: FormDlgOptions
    let change = FormDlg.create(&host.surface, options)
    let fields = buildPasswordChangeForm(change)

    @assert(change.form.rows.count == 2)
    @assert(change.form.rows[0].field == cast(*Wnd) fields.replacement)
    @assert(change.form.rows[0].label.name.raw == texts.ui_NewPassword)
    @assert(change.form.rows[1].field == cast(*Wnd) fields.confirm)
    openAndDismiss(&host, change)

    let resize       = FormDlg.create(&host.surface, options)
    let resizeFields = buildVaultResizeForm(resize)

    @assert(resize.form.rows.count == 2)
    @assert(resize.form.rows[0].field == cast(*Wnd) resizeFields.capacity)
    @assert(resize.form.rows[0].label.name.raw == texts.ui_NewCapacity)
    @assert(resizeFields.capacity.text() == "256")
    @assert(resizeFields.unit.selectedIndex == 0)
    @assert(resizeFields.keepCapacity.isChecked())
    @assert(!resizeFields.capacity.isEnabled())
    @assert(!resizeFields.unit.isEnabled())
    resizeFields.keepCapacity.toggle()
    @assert(resizeFields.capacity.isEnabled())
    @assert(resizeFields.unit.isEnabled())
    openAndDismiss(&host, resize)

    var currentFiles: Array'String
    currentFiles.add(String.from("C:\\keys\\first.key"))
    let keyFiles      = FormDlg.create(&host.surface, options)
    let keyFileFields = buildKeyFileChangeForm(keyFiles, currentFiles.toSlice())
    @assert(keyFiles.form.rows.count == 1)
    @assert(keyFiles.form.rows[0].field == cast(*Wnd) keyFileFields)
    @assert(keyFileFields.samePaths(currentFiles.toSlice()))
    openAndDismiss(&host, keyFiles)
}

// Every change box ends up as tall as what it asks for, in every language.
//
// A dialog height is measured, not authored: a help paragraph takes one more line in a language
// that says the same thing in more words, and a box tuned on English cuts that line off with
// nothing reporting it.
#test
{
    var host: Testing.HeadlessHost
    discard testSetupMainWindow(&host)
    defer host.shutdown()
    defer discard catch g_App.setLanguage(ReferenceLanguage)

    func assertFormFits(host: *Testing.HeadlessHost, dialog: *FormDlg)
    {
        openAndDismiss(host, dialog)
        let form   = dialog.form
        let needed = form.measure({form.position.width, 0}).preferred.y
        if needed > form.position.height + 0.5
        {
            Console.println("form does not end inside its box: needs ", needed, ", box holds ", form.position.height)
            @assert(false)
        }
    }

    for &one in languages()
    {
        expect g_App.setLanguage(one.tag.toString())
        host.notify(.LanguageChanged)

        var options: FormDlgOptions

        let change = FormDlg.create(&host.surface, options)
        discard buildPasswordChangeForm(change)
        assertFormFits(&host, change)

        let resize = FormDlg.create(&host.surface, options)
        discard buildVaultResizeForm(resize)
        assertFormFits(&host, resize)

        var currentFiles: Array'String
        currentFiles.add(String.from("C:\\keys\\first.key"))
        let keyFiles = FormDlg.create(&host.surface, options)
        discard buildKeyFileChangeForm(keyFiles, currentFiles.toSlice())
        assertFormFits(&host, keyFiles)
    }
}

// The drives card shows a table only while it has a drive to put in it, and says so
// plainly the rest of the time.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    window.privacyMode = false
    window.applyPrivacyControl()

    @assert(!window.mountedDrives.list.isLocallyVisible())
    @assert(window.mountedDrives.empty.isLocallyVisible())
    @assert(window.mountedDrives.selectedIndex() == Swag.U64.Max)
    @assert(!window.mountedDrives.unmountButton.isEnabled())

    window.mountedDrives.drives.add({null, String.from("C:\\vaults\\one"), String.from("mount-x"), String.from("X:"), true, false, false, 256 * 1024 * 1024, 192 * 1024 * 1024})
    window.mountedDrives.drives.add({null, String.from("C:\\vaults\\two"), String.from("mount-y"), String.from("Y:"), false, false, true, 2 * 1024 * 1024 * 1024, 1536 * 1024 * 1024})
    window.mountedDrives.refresh()

    @assert(window.mountedDrives.list.isLocallyVisible())
    @assert(!window.mountedDrives.empty.isLocallyVisible())
    @assert(window.mountedDrives.list.lineCount() == 2)

    // The row a drive occupies is the row the drive list gives it, and the mark it carries
    // travels with it. A row names the vault, not the folder it happens to sit in.
    @assert(!window.mountedDrives.list.isLineChecked(0))
    @assert(window.mountedDrives.list.isLineChecked(1))
    @assert(window.mountedDrives.list.lineAt(1)!.itemAt(cast(u32) MountedColumn.Drive).name.raw == "Y:")
    @assert(window.mountedDrives.list.lineAt(1)!.itemAt(cast(u32) MountedColumn.Size).name.raw == "2 GiB")
    @assert(window.mountedDrives.list.lineAt(1)!.itemAt(cast(u32) MountedColumn.Available).name.raw == "1536 MiB")
    @assert(window.mountedDrives.list.lineAt(1)!.itemAt(cast(u32) MountedColumn.Vault).name.raw == "two")

    // The list opens on its first row, so the one action of the card is live straight away.
    window.setState(.Ready)
    @assert(window.mountedDrives.selectedIndex() == 0)
    @assert(window.mountedDrives.unmountButton.isEnabled())

    // Handing a drive over drops its row, and the card goes back to its one line with the last.
    discard window.mountedDrives.detach(0)
    @assert(window.mountedDrives.list.lineCount() == 1)
    discard window.mountedDrives.detach(0)
    @assert(window.mountedDrives.empty.isLocallyVisible())
    @assert(!window.mountedDrives.unmountButton.isEnabled())
}

// Checking a drive puts it in the list sVaultDrive mounts at its next start, and unchecking it
// takes it back out. Unmounting the drive afterwards leaves the mark alone.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    window.privacyMode = false
    window.applyPrivacyControl()

    window.mountedDrives.drives.add({null, String.from("C:\\one"), String.from("mount-x"), String.from("X:"), true, false, false, 0, 0})
    window.mountedDrives.refresh()

    window.mountedDrives.list.setLineChecked(0, true)
    @assert(window.startupVaults.count == 1)
    @assert(window.startupVaults[0].path == "C:\\one")
    @assert(window.startupVaults[0].drive == "mount-x")
    @assert(window.startupVaults[0].needsPassword)

    discard window.mountedDrives.detach(0)
    @assert(window.startupVaults.count == 1)

    window.mountedDrives.drives.add({null, String.from("C:\\one"), String.from("mount-x"), String.from("X:"), true, false, true, 0, 0})
    window.mountedDrives.refresh()
    window.mountedDrives.list.setLineChecked(0, false)
    @assert(window.startupVaults.isEmpty())
}

// A capacity is read back the way a reader wrote it, and refused when it says nothing.
#test
{
    var host: Testing.HeadlessHost
    discard testSetupMainWindow(&host)
    defer host.shutdown()

    @assert(capacityText(256 * 1024 * 1024) == "256 MiB")
    @assert(capacityText(2 * 1024 * 1024 * 1024) == "2 GiB")

    // A size that is not a whole gibibyte stays in mebibytes rather than growing a decimal.
    @assert(capacityText(1536 * 1024 * 1024) == "1536 MiB")

    @assert(parseCapacity("256", 0).bytes == 256 * 1024 * 1024)
    @assert(parseCapacity("2", 1).bytes == 2 * 1024 * 1024 * 1024)
    @assert(!parseCapacity("", 0).error.isEmpty())
    @assert(!parseCapacity("0", 0).error.isEmpty())
    @assert(!parseCapacity("12x", 0).error.isEmpty())
    @assert(!parseCapacity("18446744073709551615", 1).error.isEmpty())
}

// The creation dialog preserves the exact filename; a vault has no required extension.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    let path = Testing.tempFilePath("vaultdrive-vault-", "")
    host.acceptModalFileDialog(path)
    window.chooseContainer(window.createPath, true)

    @assert(host.autoHandled)
    @assert(window.createPath.text() == path.toString())
}

// Privacy keeps browse history off disk, but the open dialog still returns to its last folder
// while this process is running.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    let path = Testing.tempFilePath("vaultdrive-open-state-", ".vault")
    defer discard catch File.delete(path)
    discard expect File.writeAllBytes(path.toString(), [1'u8])

    host.acceptModalFileDialog(path.toString())
    window.chooseContainer(window.mountPath, false)

    @assert(host.autoHandled)
    @assert(window.mountPath.text() == path.toString())
    @assert(Path.equals(window.fileDlgState.currentFolder.toString(), Path.directoryName(path) orelse ""))

    host.clickModalButtonWhenShown(Dialog.BtnCancel)
    window.chooseContainer(window.mountPath, false)
    @assert(host.autoHandled)
    @assert(Path.equals(window.fileDlgState.currentFolder.toString(), Path.directoryName(path) orelse ""))
}

// The panel can add an existing key file, generate a cryptographically random one, and remove
// either selection without storing the paths anywhere else.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    let existing = Testing.tempFilePath("vaultdrive-key-existing-", ".key")
    defer discard catch File.delete(existing)
    discard expect File.writeAllBytes(existing.toString(), [1'u8, 2, 3])

    host.acceptModalFileDialog(existing.toString())
    window.createKeyFiles.add.sigPressed.call(cast(*Button) window.createKeyFiles.add)
    @assert(host.autoHandled)
    @assert(window.createKeyFiles.paths.count == 1)
    @assert(window.createKeyFiles.paths[0] == existing)

    let generated = Testing.tempFilePath("vaultdrive-key-random-", ".key")
    defer discard catch File.delete(generated)
    host.acceptModalFileDialog(generated.toString())
    window.createKeyFiles.generate.sigPressed.call(cast(*Button) window.createKeyFiles.generate)
    @assert(host.autoHandled)
    @assert(window.createKeyFiles.paths.count == 2)
    @assert((expect File.info(generated.toString())).size == 64)

    window.createKeyFiles.files.setSelectedIndex(0, notify: false)
    window.createKeyFiles.remove.sigPressed.call(cast(*Button) window.createKeyFiles.remove)
    @assert(window.createKeyFiles.paths.count == 1)
    @assert(window.createKeyFiles.paths[0] == generated)
}

// A container dropped on the path field of a card fills it, exactly as browsing to it would.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    window.showTab(MainWindow.OpenTabIndex)
    @assert(host.dropFilesOnWnd(window.mountPath, ["c:/vaults/private"]) == DropEffect.Copy)
    @assert(window.mountPath.text() == "c:/vaults/private")

    // Filling the field is what makes the action live, whether a dialog or a drop wrote it.
    @assert(window.mountButton.isEnabled())
}

// A container dropped anywhere else on the window opens the page that mounts one.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    window.showTab(0)
    @assert(host.dropFilesOnWnd(window, ["c:/vaults/private"]) == DropEffect.Copy)

    @assert(window.tabs.selectedIndex == MainWindow.OpenTabIndex)
    @assert(window.mountPath.text() == "c:/vaults/private")
    @assert(window.mountPath.hasFocus())
}

// A filename extension never decides whether a dropped file is a container.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    window.showTab(0)
    @assert(host.dropFilesOnWnd(window, ["c:/vaults/private.anything"]) == DropEffect.Copy)
    @assert(window.tabs.selectedIndex == MainWindow.OpenTabIndex)
    @assert(window.mountPath.text() == "c:/vaults/private.anything")

    // Two files name no single vault to open.
    window.showTab(0)
    window.mountPath.setText("")
    @assert(host.dropFilesOnWnd(window, ["c:/vaults/a", "c:/vaults/b"]) == DropEffect.None)
    @assert(window.tabs.selectedIndex == 0)
}

// What the shipped window looks like.
//
// The tests above read the window: they ask what a button says, whether a form can act, whether
// the layout holds a language. None of them can see it. This image is the only thing that reports
// a color that stopped reading, a control that lost its ground, or a row that drifted out of its
// column - the class of defect an assertion never catches because nothing about it is wrong enough
// to fail.
//
// It is the page the window opens on. The other three are pinned by the containment test above,
// which brings each one up and measures it in every language; what an image adds over that is the
// look of the surface, and the four pages share it.
//
// It is one image, of the palette sVaultDrive ships on. Photographing the other two costs a full
// repaint of the whole surface each, which is minutes on the default configuration, and the
// palettes themselves are already pinned by the toolkit's own tests. To review them by hand, put
// `setDark` and `setLight` on their own hosts here and read the images: one host
// per palette, never one host repainted, because a render target keeps what the last paint left
// and a translucent fill then composites over the palette before it.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    host.theme.setSwagDark()

    // The chrome is not part of what this image pins: a headless surface has no desktop under it,
    // so its shadow falls on nothing and its rounded corner only punches holes in the captured
    // pixels. `HeadlessHost.setup` squares it for that reason, and applying a palette puts the
    // geometry of that palette back, so it is squared again here.
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    window.applyLayout()
    host.settleAnimations(window, 6)

    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, "vaultdrive.surface")
}
