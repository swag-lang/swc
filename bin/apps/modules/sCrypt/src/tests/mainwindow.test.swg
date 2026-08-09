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
    for [offset] in @countof(bytes) - @countof(needle) + 1
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
    }

    window.showTab(0)
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
    let unmount      = window.mountedDrives.unmountButton
    let englishWidth = unmount.position.width
    window.chooseLanguage(2)
    host.notify(.LanguageChanged)

    @assert(unmount.text() == "Démonter")
    @assert(window.createButton.text() == "Créer le coffre chiffré")
    @assert(unmount.position.width != englishWidth)

    // The third card follows too, headings and all.
    @assert(window.mountedDrives.list.header.itemAt(cast(u32) MountedColumn.Startup).name.raw == "AU DÉMARRAGE")
    @assert(window.mountedDrives.empty.text() == "Aucun lecteur monté.")

    window.chooseLanguage(1)
    host.notify(.LanguageChanged)
    @assert(unmount.text() == "Unmount")
    @assert(unmount.position.width == englishWidth)
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

// The last successful mount prepares the next open-vault form without retaining a credential.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    let drive = window.selectedMountPoint()
    @assert(!drive.isEmpty())

    window.operation.path     = String.from("C:\\vaults\\remembered.scrypt")
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

    window.mountSettings = {}
    window.mountPath.setText("")
    window.readOnly.setState(.Unchecked)
    window.mountPassword.clear()
    loadMainWindowState(window, state.toSlice())

    @assert(window.mountPath.text() == "C:\\vaults\\remembered.scrypt")
    @assert(window.selectedMountPoint() == drive)
    @assert(window.readOnly.isChecked())
    @assert(window.mountPassword.isEmpty())
}

// The page on show is reachable from the keyboard, in the order it reads, and it is the only
// page in the ring.
//
// The strip comes first, because moving between the three pages is the first thing the keyboard
// can do here. A card is built with its action bar docked under a form that fills the space left
// over, so this also pins that the traversal follows the arranged rectangles rather than the
// order the windows were created in.
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
    @assert(order.stops.count == 8)
    @assert(order.stops[0] == cast(*Wnd) window.tabs)
    @assert(order.stops[1] == cast(*Wnd) window.createPath)
    @assert(order.stops[7] == cast(*Wnd) window.languageChoice)

    // Live, each action takes its place after the card it answers for, and the dominant one
    // comes last on its card because the bar stacks from its right edge.
    window.createButton.enable(true)
    window.mountButton.enable(true)
    window.resizeButton.enable(true)
    window.passwordButton.enable(true)

    let full = Gui.FocusOrder.collect(window)
    @assert(full.stops.count == 9)
    @assert(full.stops[0] == cast(*Wnd) window.tabs)
    @assert(full.stops[1] == cast(*Wnd) window.createPath)
    @assert(full.stops[2] == cast(*Wnd) window.browseCreate)
    @assert(full.stops[3] == cast(*Wnd) window.createSize)
    @assert(full.stops[4] == cast(*Wnd) window.createUnit)
    @assert(full.stops[5] == cast(*Wnd) window.createPassword)
    @assert(full.stops[6] == cast(*Wnd) window.confirmPassword)
    @assert(full.stops[7] == cast(*Wnd) window.createButton)
    @assert(full.stops[8] == cast(*Wnd) window.languageChoice)

    // Bringing up another page swaps the whole middle of the ring for that page's controls, and
    // the dominant action still comes last on its card because the bar stacks from its right edge.
    window.showTab(1)
    let opened = Gui.FocusOrder.collect(window)
    @assert(opened.stops.count == 10)
    @assert(opened.stops[0] == cast(*Wnd) window.tabs)
    @assert(opened.stops[1] == cast(*Wnd) window.mountPath)
    @assert(opened.stops[2] == cast(*Wnd) window.browseMount)
    @assert(opened.stops[3] == cast(*Wnd) window.mountPassword)
    @assert(opened.stops[4] == cast(*Wnd) window.drive)
    @assert(opened.stops[5] == cast(*Wnd) window.readOnly)
    @assert(opened.stops[6] == cast(*Wnd) window.passwordButton)
    @assert(opened.stops[7] == cast(*Wnd) window.resizeButton)
    @assert(opened.stops[8] == cast(*Wnd) window.mountButton)
    @assert(opened.stops[9] == cast(*Wnd) window.languageChoice)

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

        dref frames += 1
        if dref frames == 1 do
            host.keyPress(Input.Key.Escape)
        elif dref frames > 30
        {
            dref forced = true
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

// A form with no password in it is a form that can act: an empty password is a vault that
// opens without one, not a field left blank.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    @assert(!window.canCreate())
    window.createPath.setText("C:\\open.scrypt")
    @assert(window.canCreate())
    @assert(window.createButton.isEnabled())

    // The two actions that change a container need the file and nothing else: the password they
    // act on is the one their own box asks for, never what this card happens to be holding.
    @assert(!window.canModifyVault())
    window.mountPath.setText("C:\\open.scrypt")
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

// A box that changes a vault opens on the password the vault already has.
//
// This is the whole of the rule: the container refuses a wrong password either way, so what the
// box adds is that the reader has to say it. Read off the open card instead, a password typed to
// mount a drive becomes permission to take the vault over, and a field left filled in hands that
// permission to whoever reaches the keyboard next.
#test
{
    var host: Testing.HeadlessHost
    discard testSetupMainWindow(&host)
    defer host.shutdown()

    let texts = appStrings()

    var options: FormDlgOptions
    let change = FormDlg.create(&host.surface, options)
    let fields = buildPasswordChangeForm(change)

    @assert(change.form.rows.count == 3)
    @assert(change.form.rows[0].field == cast(*Wnd) fields.current)
    @assert(change.form.rows[0].label.name.raw == texts.ui_CurrentPassword)
    @assert(change.form.rows[1].field == cast(*Wnd) fields.replacement)
    @assert(change.form.rows[2].field == cast(*Wnd) fields.confirm)
    openAndDismiss(&host, change)

    // Growing asks the same question first, and in the same words: one shape for every box that
    // changes a vault is one thing to learn instead of two.
    let grow       = FormDlg.create(&host.surface, options)
    let growFields = buildVaultGrowForm(grow, 512 * 1024 * 1024)

    @assert(grow.form.rows.count == 2)
    @assert(grow.form.rows[0].field == cast(*Wnd) growFields.current)
    @assert(grow.form.rows[0].label.name.raw == texts.ui_CurrentPassword)
    @assert(growFields.capacity.text() == "512")
    @assert(growFields.unit.selectedIndex == 0)
    openAndDismiss(&host, grow)
}

// Both boxes end up as tall as what they ask for, in every language.
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

        let grow = FormDlg.create(&host.surface, options)
        discard buildVaultGrowForm(grow, 512 * 1024 * 1024)
        assertFormFits(&host, grow)
    }
}

// The drives card shows a table only while it has a drive to put in it, and says so
// plainly the rest of the time.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    @assert(!window.mountedDrives.list.isLocallyVisible())
    @assert(window.mountedDrives.empty.isLocallyVisible())
    @assert(window.mountedDrives.selectedIndex() == Swag.U64.Max)
    @assert(!window.mountedDrives.unmountButton.isEnabled())

    window.mountedDrives.drives.add({null, String.from("C:\\vaults\\one.scrypt"), String.from("X:"), true, false, false})
    window.mountedDrives.drives.add({null, String.from("C:\\vaults\\two.scrypt"), String.from("Y:"), false, false, true})
    window.mountedDrives.refresh()

    @assert(window.mountedDrives.list.isLocallyVisible())
    @assert(!window.mountedDrives.empty.isLocallyVisible())
    @assert(window.mountedDrives.list.lineCount() == 2)

    // The row a drive occupies is the row the drive list gives it, and the mark it carries
    // travels with it. A row names the vault, not the folder it happens to sit in.
    @assert(!window.mountedDrives.list.isLineChecked(0))
    @assert(window.mountedDrives.list.isLineChecked(1))
    @assert(window.mountedDrives.list.lineAt(1)!.itemAt(cast(u32) MountedColumn.Drive).name.raw == "Y:")
    @assert(window.mountedDrives.list.lineAt(1)!.itemAt(cast(u32) MountedColumn.Vault).name.raw == "two.scrypt")

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

// Checking a drive puts it in the list sCrypt mounts at its next start, and unchecking it
// takes it back out. Unmounting the drive afterwards leaves the mark alone.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    window.mountedDrives.drives.add({null, String.from("C:\\one.scrypt"), String.from("X:"), true, false, false})
    window.mountedDrives.refresh()

    window.mountedDrives.list.setLineChecked(0, true)
    @assert(window.startupVaults.count == 1)
    @assert(window.startupVaults[0].path == "C:\\one.scrypt")
    @assert(window.startupVaults[0].drive == "X:")
    @assert(window.startupVaults[0].needsPassword)

    discard window.mountedDrives.detach(0)
    @assert(window.startupVaults.count == 1)

    window.mountedDrives.drives.add({null, String.from("C:\\one.scrypt"), String.from("X:"), true, false, true})
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

// A container dropped on the path field of a card fills it, exactly as browsing to it would.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    window.showTab(MainWindow.OpenTabIndex)
    @assert(host.dropFilesOnWnd(window.mountPath, ["c:/vaults/private.scrypt"]) == DropEffect.Copy)
    @assert(window.mountPath.text() == "c:/vaults/private.scrypt")

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
    @assert(host.dropFilesOnWnd(window, ["c:/vaults/private.scrypt"]) == DropEffect.Copy)

    @assert(window.tabs.selectedIndex == MainWindow.OpenTabIndex)
    @assert(window.mountPath.text() == "c:/vaults/private.scrypt")
    @assert(window.mountPath.hasFocus())
}

// Anything that is not a container is refused, and leaves the window where it was.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    window.showTab(0)
    @assert(host.dropFilesOnWnd(window, ["c:/photos/holiday.png"]) == DropEffect.None)
    @assert(window.tabs.selectedIndex == 0)
    @assert(window.mountPath.text() == "")

    // Two containers name no single vault to open.
    @assert(host.dropFilesOnWnd(window, ["c:/vaults/a.scrypt", "c:/vaults/b.scrypt"]) == DropEffect.None)
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
// It is the page the window opens on. The other two are pinned by the containment test above,
// which brings each one up and measures it in every language; what an image adds over that is the
// look of the surface, and the three pages share it.
//
// It is one image, of the palette sCrypt ships on. Photographing the other three costs a full
// repaint of the whole surface each, which is minutes on the default configuration, and the
// palettes themselves are already pinned by the toolkit's own tests. To review them by hand, put
// `setSwagLight`, `setDark` and `setLight` on their own hosts here and read the images: one host
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
    Pixel.Testing.assertImageGolden(&image, "scrypt.surface")
}
