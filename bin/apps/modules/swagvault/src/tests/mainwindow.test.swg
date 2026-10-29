#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui

// A completed worker keeps its typed failure; the UI localizes it in the language active at presentation.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer discard catch g_App.setLanguage(ReferenceLanguage)
    expect g_App.setLanguage(ReferenceLanguage)
    let path = Testing.tempFilePath("vault-operation-", ".bin")
    defer discard catch File.delete(path)

    window.operation.kind = .Create
    window.operation.path = path
    window.operation.size = MinimumSize - 1
    window.operation.task.submit(func|window|() { window.runOperation() })
    window.operation.task.wait()
    expect g_App.setLanguage("fr")
    let expectedFirst = Format.toString(appStrings().msg_SizeMinimum, (MinimumSize + 1024 * 1024 - 1) / (1024 * 1024))
    var firstMessage: String
    scope
    {
        var firstErrorOutcome: Swag.Error
        catch window.operation.error.raise() as firstErrorOutcome
        let firstError = firstErrorOutcome.value()
        Swag.assert(firstError != null and not isCanceledError(firstError))
        firstMessage = caughtMessage(firstError)
        Swag.assert(firstMessage == expectedFirst)
    }

    window.operation.error.reset()
    expect g_App.setLanguage(ReferenceLanguage)
    window.operation.size = MinimumSize
    window.operation.progress.cancel()
    window.operation.task.submit(func|window|() { window.runOperation() })
    window.operation.task.wait()
    scope
    {
        var canceledErrorOutcome: Swag.Error
        catch window.operation.error.raise() as canceledErrorOutcome
        let canceledError = canceledErrorOutcome.value()
        Swag.assert(canceledError != null and isCanceledError(canceledError))
        let message = caughtMessage(canceledError)
        Swag.assert(message == appStrings().msg_OperationStopped)
    }

    Swag.assert(firstMessage == expectedFirst)
    Swag.assert(not File.exists(path))

    window.operation.error.reset()
    window.operation.kind = .Unmount
    window.operation.task.submit(func|window|() { window.runOperation() })
    window.operation.task.wait()
    Swag.assert(window.operation.error.isEmpty())
    window.operation.kind = .None
}

// Builds the real main window, at its smallest size, inside the frame of the shipped surface.
func testSetupMainWindow(host: *Testing.HeadlessHost, scale = 1.0'f32)->*MainWindow
{
    host.setup(cast(f32, MainWindow.MinWidth), cast(f32, MainWindow.MinHeight), scale)
    host.surface.updateFlags(SurfaceFlags.StandardWindow | SurfaceFlags.NoShadow)

    // The strip starts with the application's glyph, as the shipped window does.
    host.app.setAppIcon(expect Pixel.Image.decode(".png", AppIcon))
    host.bindApplication(&g_App)

    // The window resolves its application through its surface, so that is the one a language
    // switch travels through and the one that has to be able to find the translations. The
    // module global gets them too, because the code under test reads `g_App` directly.
    registerAppStrings(&g_App.resources)
    registerAppStrings(&host.app.resources)

    // Built on the surface root, the way the application builds it: the window installs itself
    // as the view of its surface, which destroys whatever view was there before.
    let result = MainWindow.create(&host.surfaceWnd)

    host.surface.setTitle(ProductName)
    result.applyLayout()
    return result
}

// Gives the window one mount destination of its own, so free host drives never change a result.
func useTestDestination(window: *MainWindow)
{
    window.mountDestinations.clear()
    window.mountDestinations.add(MountDestination{"D:", "D:"})
    window.drive.clear()
    window.drive.addItem("D:")
    window.drive.setSelectedIndex(0, notify: false)
}

// Fills the list the way the charter pictures it: one vault mounted, two at rest.
func fillPictureList(window: *MainWindow)
{
    useTestDestination(window)
    window.privacyMode = false
    window.applyPrivacyControl()
    window.vaults.add(KnownVault{"C:\\Users\\vault\\papiers.bin", "D:", false})
    window.vaults.add(KnownVault{"C:\\vault.bin", "D:", false})
    window.vaults.add(KnownVault{"E:\\archives-2025.bin", "D:", false})
    window.mountedDrives.drives.add(MountedDrive{null, "C:\\Users\\vault\\papiers.bin", "P:", "P:", true, false, false, 2 * 1024 * 1024 * 1024, 0})
    window.refreshVaults()
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
    if not needle.count or needle.count > bytes.count do
        return false
    for offset in bytes.count - needle.count + 1
    {
        if Swag.memcmp(bytes.buffer + offset, needle.buffer, needle.count) == 0 do
            return true
    }

    return false
}

// Reports whether the lens of `window` shows an entry titled `title`.
func lensHasEntry(window: *MainWindow, title: string)->bool
{
    for section in window.lens.results.sections
    {
        for &entry in section!.entries where entry.title == title do
            return true
    }

    return false
}

// Fails when `column` reaches past the bottom of `page`, or into the hint line standing over it:
// a page at the window's smallest size still shows all it holds.
func assertColumnFits(window: *MainWindow, page: *Wnd, column: *Wnd)
{
    var room = page.clientRect().height
    if window.hintLine.isLocallyVisible() do
        room = Math.min(room, window.hintLine.position.y)
    if column.position.bottom() > room + 0.5
    {
        Console.println("page column does not fit: ends at ", column.position.bottom(), ", page holds ", room)
        Swag.assert(false)
    }
}

// The window is built in the reference language, on the list, whatever the language of the account.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    Swag.assert(activeLanguage() == ReferenceLanguage)
    Swag.assert(window.page == .List)
    Swag.assert(window.list.title.text() == "Vaults")
    Swag.assert(window.createButton.text() == "Create Encrypted Vault")
    Swag.assert(window.language == ReferenceLanguage)

    // The appearance action keeps the choice and its persistence, and draws nothing: the theme,
    // the language and About are lens entries.
    Swag.assert(window.appearanceButton.parent == &host.surfaceWnd)
    Swag.assert(not window.appearanceButton.isLocallyVisible())

    window.themeIndex = cast(u32, AppearanceTheme.Dark)
    window.applyTheme()
    Swag.assert(window.appearanceButton.appearanceTheme == .Dark and host.theme.colors.ground == ThemeColors.encrePalette().ground)
    window.themeIndex = cast(u32, AppearanceTheme.Light)
    window.applyTheme()
    Swag.assert(window.appearanceButton.appearanceTheme == .Light and host.theme.colors.ground == ThemeColors.papierPalette().ground)
    window.themeIndex = cast(u32, AppearanceTheme.System)
    window.applyTheme()
    Swag.assert(window.appearanceButton.appearanceTheme == .System and host.theme.colors.ground == ThemeColors.encrePalette().ground)
}

// Privacy is the default: no vault path reaches the state, and the list keeps only what is
// mounted or being unlocked.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    Swag.assert(window.privacyMode)
    Swag.assert(not window.protectHiddenOnMount)
    Swag.assert(window.privacyModeControl.isChecked())

    window.openVault("C:\\private\\unlisted")
    Swag.assert(window.vaults.count == 1 and window.chosenPath == "C:\\private\\unlisted")
    window.startupVaults.add(StartupVault{"C:\\private\\startup", "mount-x", true, false})
    window.fileDlgState.currentFolder = "C:\\private\\browse-private"
    var state = saveMainWindowState(window)
    Swag.assert(not containsStateBytes(state.toSlice(), "unlisted"))
    Swag.assert(not containsStateBytes(state.toSlice(), "startup"))
    Swag.assert(not containsStateBytes(state.toSlice(), "browse-private"))

    // Folded, a locked vault leaves the list at once.
    window.foldVault()
    Swag.assert(window.vaults.isEmpty())
    Swag.assert(window.list.rows.isEmpty())

    window.clearPrivateState()
    Swag.assert(window.startupVaults.isEmpty())
}

// About is a lens entry, and reaches the standard application box.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    Swag.assert(not window.appearanceButton.sigAboutRequested.isEmpty())
    host.clickModalButtonWhenShown(Dialog.BtnCancel)
    window.showAbout()
    host.pump()

    Swag.assert(host.autoHandled)
    Swag.assert(host.openedSurfaceCount() == 0)
}

// Every page holds what it shows in every shipped language, at the window's smallest size and at
// the scales a display commonly uses: nothing is arranged smaller than the text it has to show,
// and no column runs past the bottom of its page.
#test
{
    defer discard catch g_App.setLanguage(ReferenceLanguage)
    for scale in [1.0'f32, 1.5'f32]
    {
        var host: Testing.HeadlessHost
        let window = testSetupMainWindow(&host, scale)
        useTestDestination(window)
        window.openVault("C:\\vaults\\one")

        for &one in languages()
        {
            expect g_App.setLanguage(one.tag)
            host.notify(.LanguageChanged)

            window.showPage(.List, animate: false)
            Testing.assertContentFits(window)
            let card = &window.list.card
            Swag.assert(card.panel.isLocallyVisible())
            Swag.assert(card.form.position.bottom() <= card.options.position.y + 0.5)
            Swag.assert(card.mount.position.bottom() <= card.panel.position.height + 0.5)
            for child in card.options.children where child.isLocallyVisible() do
                Swag.assert(card.options.position.x + child.position.right() <= card.mount.position.x + 0.5)

            window.showPage(.Create, animate: false)
            Testing.assertContentFits(window)
            assertColumnFits(window, window.createPage, window.createPage.column)
            let create = window.createPage
            Swag.assert(create.cancel.position.right() <= create.createAction.position.x)
            Swag.assert(create.keyFiles.position.right() <= create.cancel.position.x)

            window.progressPage.begin("C:\\vaults\\one", appStrings().ui_Randomizing, appStrings().ui_RandomizeHelp, appStrings().ui_StopCreating)
            window.showPage(.Progress, animate: false)
            Testing.assertContentFits(window)
            assertColumnFits(window, window.progressPage, window.progressPage.column)

            window.showPage(.Options, animate: false)
            Testing.assertContentFits(window)
            assertColumnFits(window, window.optionsPage, window.optionsPage.column)
        }

        window.showPage(.List, animate: false)
    }
}

// A page change arrives quietly: the incoming page fades in from its side and settles, while the
// keyboard is already on it.
#[Swag.TestTag("animation.vault")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    host.setReducedMotion(false)
    host.settleAnimations(window)

    window.showPage(.Create)
    Swag.assert(window.createPath.hasFocus())
    host.advanceAnimations(0.05)
    Swag.assert(window.createPage.presentationOpacity > 0 and window.createPage.presentationOpacity < 1)
    host.app.animator.finishAll()
    Swag.assert(window.createPage.presentationOpacity == 1)
    Swag.assert(not window.list.scroll.isLocallyVisible())
}

// A language switch re-labels the complete surface.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer discard catch g_App.setLanguage(ReferenceLanguage)

    fillPictureList(window)
    let row = window.list.rows[0]

    // Entry zero follows the account, so the registered languages start at one: one is the
    // reference language and two is French. Going through the picker is what the user does, and
    // it is what carries the change all the way to the labels.
    expect window.appearanceButton.setAppearanceLanguage("fr", notify: true)
    host.notify(.LanguageChanged)

    Swag.assert(window.list.title.text() == "Coffres")
    Swag.assert(row.unmount.text() == "Démonter")
    Swag.assert(row.open.text() == "Ouvrir P:")
    Swag.assert(window.createButton.text() == "Créer le coffre chiffré")
    Swag.assert(window.mountButton.text() == "Monter")
    Swag.assert(window.optionsPage.head.title.text() == "Vie privée")
    Swag.assert(Utf8.startsWith(window.vaultIdentity("C:\\Users\\vault\\papiers.bin"), "monté sur P:"))

    expect window.appearanceButton.setAppearanceLanguage(ReferenceLanguage, notify: true)
    host.notify(.LanguageChanged)
    Swag.assert(row.unmount.text() == "Unmount")
}

// Picking a language remembers it, and the system entry restores "follow the account".
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer discard catch g_App.setLanguage(ReferenceLanguage)

    // The window opens on the reference language rather than on the account.
    Swag.assert(window.appearanceButton.language == ReferenceLanguage)

    expect window.appearanceButton.setAppearanceLanguage("fr", notify: true)
    host.notify(.LanguageChanged)
    Swag.assert(window.language == "fr")
    Swag.assert(activeLanguage() == "fr")
    Swag.assert(window.appearanceButton.language == "fr")

    expect window.appearanceButton.setAppearanceLanguage("", notify: true)
    Swag.assert(window.language.isEmpty())
    Swag.assert(activeLanguage() == systemLanguage())
}

// With privacy mode off, the list remembers each vault with the drive and the read-only choice of
// its last mount, and never a credential.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    useTestDestination(window)

    window.privacyMode = false
    window.applyPrivacyControl()

    window.operation.path       = "C:\\vaults\\remembered"
    window.operation.mount      = "D:"
    window.operation.mountLabel = "D:"
    window.operation.readOnly   = true
    window.rememberMountedDrive()
    Swag.assert(window.vaults.count == 1)
    Swag.assert(window.vaults[0].drive == "D:" and window.vaults[0].readOnly)

    // Put unmistakable bytes in the password storage. Persistent state must never observe them.
    let secret = "not a setting"
    Swag.memcpy(&window.mountPassword.storage[0], secret.buffer, secret.count)
    window.mountPassword.byteCount = secret.count

    var state       = saveMainWindowState(window)
    let secretBytes = cast(const [..] u8, secret)
    Swag.assert(not containsStateBytes(state.toSlice(), secretBytes))

    window.unlockKeyFiles.add("C:\\private\\access.key")
    state = saveMainWindowState(window)
    Swag.assert(not containsStateBytes(state.toSlice(), "access.key"))

    window.mountedDrives.drives.clear()
    window.vaults.clear()
    window.forgetAccess()
    loadMainWindowState(window, state.toSlice())

    Swag.assert(window.vaults.count == 1)
    Swag.assert(window.vaults[0].path == "C:\\vaults\\remembered")
    Swag.assert(window.vaults[0].drive == "D:" and window.vaults[0].readOnly)
    Swag.assert(window.mountPassword.isEmpty())
    Swag.assert(window.unlockKeyFiles.isEmpty())

    // Choosing it again starts from the choices of its last mount.
    window.chooseVault("C:\\vaults\\remembered")
    Swag.assert(window.readOnly.isChecked())
    Swag.assert(window.selectedMountPoint() == "D:")
}

// The last mount an earlier version saved joins the list once.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    var legacy:     ConcatBuffer
    var encoder:    Serialization.Encoder'Serialization.Write.TagBin
    var serializer: Serialization.Serializer
    var privacy  = false
    var settings = MountSettings{"C:\\vaults\\legacy", "mount-x", true}
    expect serializer.startWrite(&encoder, &legacy)
    expect serializer.beginSection(.Unordered)
    expect serializer.serialize("MainWindow.privacyMode", &privacy)
    expect serializer.serialize("MainWindow.mountSettings", &settings)
    expect serializer.endSection()
    expect serializer.end()

    let bytes = legacy.toString()
    loadMainWindowState(window, bytes.toSlice())
    Swag.assert(window.vaults.count == 1 and
                window.vaults[0].path == "C:\\vaults\\legacy" and
                window.vaults[0].readOnly)
}

// Automatic-unmount choices are explicit persistent policy, and the timeout is only actionable
// while inactivity handling is enabled.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    Swag.assert(window.unmountOnLock.isChecked())
    Swag.assert(window.unmountOnSuspend.isChecked())
    Swag.assert(not window.unmountOnIdle.isChecked())
    Swag.assert(not window.idleTimeout.isEnabled())

    window.unmountOnLock.toggle()
    window.unmountOnIdle.toggle()
    window.optionsPage.setTimeout(2)
    window.readAutoUnmountControls()
    var state = saveMainWindowState(window)

    window.autoUnmount = {}
    window.applyAutoUnmountControls()
    loadMainWindowState(window, state.toSlice())

    Swag.assert(not window.autoUnmount.onSessionLock)
    Swag.assert(window.autoUnmount.onSuspend)
    Swag.assert(window.autoUnmount.onIdle)
    Swag.assert(window.autoUnmount.idleMinutes == 30)
    Swag.assert(window.idleTimeout.isEnabled())

    // The switches are lens entries too, and the lens says which are on.
    discard window.runCommand(VaultCommands.UnmountOnSuspend)
    Swag.assert(not window.autoUnmount.onSuspend)
}

// A configured event closes protected drives only. An unprotected container has no key to wipe
// and remains mounted, while startup marks remain policy for the next application start.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    window.mountedDrives.drives.add(MountedDrive{null, "C:\\protected", "mount-x", "X:", true, false, true, 0, 0})
    window.mountedDrives.drives.add(MountedDrive{null, "C:\\open", "mount-y", "Y:", false, false, false, 0, 0})
    window.addVault("C:\\protected")
    window.addVault("C:\\open")
    window.refreshVaults()
    window.handleAutoUnmount(.SessionLock)

    Swag.assert(window.mountedDrives.drives.count == 1)
    Swag.assert(window.mountedDrives.drives[0].path == "C:\\open")
    Swag.assert(window.statusMessage == .AutoUnmounted)

    // With privacy mode on, the closed vault leaves the list with its drive.
    Swag.assert(window.vaults.count == 1 and window.list.rows.count == 1)

    window.autoUnmount.onSessionLock = false
    window.mountedDrives.drives.add(MountedDrive{null, "C:\\second", "mount-z", "Z:", true, false, false, 0, 0})
    window.handleAutoUnmount(.SessionLock)
    Swag.assert(window.mountedDrives.drives.count == 2)
}

// The keyboard opens on the first thing there is to do, and walks the unfolded vault in the order
// it reads: its password, then its choices, then Mount.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    useTestDestination(window)

    // An empty list opens on the way to a new vault.
    Swag.assert(window.list.newVault.hasFocus())

    window.openVault("C:\\vaults\\one")
    Swag.assert(window.mountPassword.hasFocus())
    Swag.assert(window.mountButton.isEnabled())
    host.keyPress(Input.Key.Tab)
    Swag.assert(window.drive.hasFocus())
    host.keyPress(Input.Key.Tab)
    Swag.assert(window.list.card.keyFiles.hasFocus())
    host.keyPress(Input.Key.Tab)
    Swag.assert(window.readOnly.hasFocus())
    host.keyPress(Input.Key.Tab)
    Swag.assert(window.mountButton.hasFocus())

    // Escape folds the vault, and the keyboard goes back to the list.
    window.readOnly.setFocus()
    host.keyPress(Input.Key.Escape)
    Swag.assert(window.chosenPath.isEmpty())
    Swag.assert(not window.list.card.panel.isLocallyVisible())

    // The create page opens on its first field; Escape leads back to the list.
    window.showPage(.Create, animate: false)
    Swag.assert(window.createPath.hasFocus())
    host.keyPress(Input.Key.Tab)
    Swag.assert(window.browseCreate.hasFocus())
    host.keyPress(Input.Key.Escape)
    Swag.assert(window.page == .List)
}

// The file box is opened, backed out of, and left behind without the keyboard going missing.
//
// This is the whole browse gesture done from the keyboard: Tab to the action, Space to open the
// box, Escape to leave it, and the form resumes at the control the box was opened from.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    window.showPage(.Create, animate: false)
    Swag.assert(window.createPath.hasFocus())
    host.keyPress(Input.Key.Tab)
    Swag.assert(window.browseCreate.hasFocus())

    // The box runs a nested loop, so the way out is armed before it opens. Escape has to reach
    // the cancel action of the box from the file list the box opens the keyboard on. A box that
    // does not answer it is closed by hand after a few frames, so this fails on its assertion
    // rather than pumping frames until the runner gives up on it.
    var frames = 0's32
    var forced: bool
    host.app.sigFrame += func|host = &host, frames = &frames, forced = &forced|(app)
    {
        if not host.openedSurfaceCount() do
            return

        frames[] += 1
        if frames[] == 1
        {
            host.keyPress(Input.Key.Escape)
        }
        elif frames[] > 30
        {
            forced[] = true
            app.exitModal(Gui.Dialog.BtnCancel)
        }
    }

    host.keyPress(Input.Key.Space)

    // A zero frame count means the browse action never opened the box; `forced` means the box
    // opened and Escape was not what closed it.
    Swag.assert(frames != 0)
    Swag.assert(not forced)
    Swag.assert(host.openedSurfaceCount() == 0)

    // Nothing was chosen, the page is still up, and the keyboard is back where it was.
    Swag.assert((window.createPath.text()).count == 0)
    Swag.assert(window.page == .Create)
    Swag.assert(window.browseCreate.hasFocus())
}

// The notice line is named, not written, so it says the same thing in the new language; with
// nothing to say, it is not there.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer discard catch g_App.setLanguage(ReferenceLanguage)

    Swag.assert(window.statusText() == "Ready — create a vault or choose one to open.")
    Swag.assert(not window.list.notice.isLocallyVisible())

    window.statusDrive = "Z:"
    window.setStatus(.Mounted)
    Swag.assert(Utf8.contains(window.statusText(), "Z:"))
    Swag.assert(window.list.notice.isLocallyVisible())

    expect g_App.setLanguage("fr")
    Swag.assert(Utf8.startsWith(window.statusText(), "Lecteur chiffré monté sur Z:"))
}

// A failure says its sentence in the active language, not the diagnostic the layer wrote.
//
// The volume layer reports an ErrorKind and an English diagnostic for whoever reads a
// report; what the reader is shown comes from the string table.
#test
{
    var host: Testing.HeadlessHost
    discard testSetupMainWindow(&host)
    defer discard catch g_App.setLanguage(ReferenceLanguage)

    func messageFor(kind: ErrorKind)->String
    {
        var errOutcome: Swag.Error
        catch raiseVolumeError(kind) as errOutcome
        let err = errOutcome.value()
        return caughtMessage(err)
    }

    // The English diagnostic never reaches the reader, in either language.
    Swag.assert(messageFor(.PasswordOrDamaged) == "The password or key files are incorrect, or the container is damaged.")
    Swag.assert(messageFor(.Corrupted) == "The container is damaged.")
    Swag.assert(messageFor(.PasswordRequired) == "A password is required.")
    Swag.assert(messageFor(.Canceled) == "The operation stopped.")
    Swag.assert(messageFor(.General) == appStrings().msg_SystemError)

    // Every way a container can refuse to open answers the same sentence: telling wrong access
    // from a damaged container is exactly what the format refuses to do.
    Swag.assert(messageFor(.PasswordOrDamaged) != messageFor(.Corrupted))

    expect g_App.setLanguage("fr")
    Swag.assert(messageFor(.PasswordOrDamaged) == "Le mot de passe ou les fichiers clés sont incorrects, ou le conteneur est endommagé.")
    Swag.assert(messageFor(.PasswordRequired) == appStrings().msg_PasswordRequired)
    Swag.assert(messageFor(.DiskFull) == appStrings().msg_ErrDiskFull)
    Swag.assert(messageFor(.General) == appStrings().msg_SystemError)

    // A kind that means nothing to a reader reads as the generic damaged-container wording.
    Swag.assert(messageFor(.DirectoryNotEmpty) == appStrings().msg_ErrDamaged)
    Swag.assert(messageFor(.NotDirectory) == appStrings().msg_ErrDamaged)
}

// A form with no password in it is a form that can act: an empty password is a vault that
// opens without one, not a field left blank.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    useTestDestination(window)

    Swag.assert(not window.canCreate())
    Swag.assert(not window.createButton.isEnabled())
    window.createPath.setText("C:\\open")
    Swag.assert(window.canCreate())
    Swag.assert(window.createButton.isEnabled())

    // A vault the list unfolds can be mounted and changed with nothing else typed.
    Swag.assert(not window.canModifyVault())
    window.openVault("C:\\open")
    Swag.assert(window.canModifyVault())
    Swag.assert(window.canMount())
    Swag.assert(window.mountButton.isEnabled())
}

// Every command of the window is an entry of the lens, and the vaults it knows answer it too.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    useTestDestination(window)
    window.privacyMode = false
    window.applyPrivacyControl()

    let texts = appStrings()
    window.openVault("C:\\vaults\\locked")
    window.lens.open(">")
    for title in [texts.ui_NewVault, texts.ui_OpenFile, texts.ui_VaultsTitle, texts.cmd_Options,
                  texts.ui_Mount, texts.ui_ReadOnly, texts.ui_ProtectHidden, texts.ui_ChangePassword,
                  texts.ui_ChangeKeyFiles, texts.ui_Resize, texts.ui_CreateHidden, texts.ui_Forget,
                  texts.ui_PrivacyMode, texts.ui_UnmountOnLock, texts.ui_UnmountOnSuspend, texts.ui_UnmountOnIdle] do
        Swag.assert(lensHasEntry(window, title))
    window.lens.close()

    // A mounted vault offers what applies to a drive instead.
    window.mountedDrives.drives.add(MountedDrive{null, "C:\\vaults\\locked", "D:", "X:", true, false, false, 0, 0})
    window.refreshVaults()
    window.lens.open(">")
    Swag.assert(lensHasEntry(window, texts.ui_Unmount))
    Swag.assert(lensHasEntry(window, Format.toString(texts.ui_OpenDrive, "X:")))
    Swag.assert(lensHasEntry(window, texts.ui_MountAtStartup))
    Swag.assert(not lensHasEntry(window, texts.ui_Mount))
    window.lens.close()

    // At rest the lens offers what the chosen vault can do now, under its name, then the way to
    // another vault.
    window.lens.open()
    Swag.assert(window.lens.results.sections[0]!.label == "locked")
    Swag.assert(lensHasEntry(window, texts.ui_Unmount) and lensHasEntry(window, Format.toString(texts.ui_OpenDrive, "X:")))
    Swag.assert(lensHasEntry(window, texts.ui_NewVault) and lensHasEntry(window, texts.ui_OpenFile))
    Swag.assert(not lensHasEntry(window, texts.ui_MountAtStartup) and not lensHasEntry(window, texts.ui_Mount))
    window.lens.close()

    // The vaults answer a query by name.
    window.addVault("C:\\vaults\\other.bin")
    window.lens.open("other")
    Swag.assert(lensHasEntry(window, "other.bin"))
    window.lens.close()

    // Protecting the hidden volume is a choice of the next mount, said on the vault's line.
    window.chooseVault("C:\\vaults\\other.bin")
    discard window.runCommand(VaultCommands.ProtectHidden)
    Swag.assert(window.protectHiddenOnMount)
    Swag.assert(Utf8.contains(window.vaultIdentity("C:\\vaults\\other.bin"), texts.ui_StateProtected))
}

// Boxes contain only the change being made. Current password and key files stay on the unfolded
// vault, where mounting, resizing, and both access changes read the same input once.
#test
{
    var host: Testing.HeadlessHost
    discard testSetupMainWindow(&host)

    let texts = appStrings()

    var options: FormDlgOptions
    let change = FormDlg.create(&host.surface, options)
    let fields = buildPasswordChangeForm(change)

    Swag.assert(change.form.rows.count == 2)
    Swag.assert(change.form.rows[0].field == cast(*Wnd, fields.replacement))
    Swag.assert(change.form.rows[0].label.name.raw == texts.ui_NewPassword)
    Swag.assert(change.form.rows[1].field == cast(*Wnd, fields.confirm))
    openAndDismiss(&host, change)

    let resize       = FormDlg.create(&host.surface, options)
    let resizeFields = buildVaultResizeForm(resize)

    Swag.assert(resize.form.rows.count == 2)
    Swag.assert(resize.form.rows[0].field == cast(*Wnd, resizeFields.capacity))
    Swag.assert(resize.form.rows[0].label.name.raw == texts.ui_NewCapacity)
    Swag.assert(resizeFields.capacity.text() == "256")
    Swag.assert(resizeFields.unit.selectedIndex == 0)
    Swag.assert(resizeFields.keepCapacity.isChecked())
    Swag.assert(not resizeFields.capacity.isEnabled())
    Swag.assert(not resizeFields.unit.isEnabled())
    resizeFields.keepCapacity.toggle()
    Swag.assert(resizeFields.capacity.isEnabled())
    Swag.assert(resizeFields.unit.isEnabled())
    openAndDismiss(&host, resize)

    var currentFiles: Array'String
    currentFiles.add("C:\\keys\\first.key")
    let keyFiles      = FormDlg.create(&host.surface, options)
    let keyFileFields = buildKeyFileChangeForm(keyFiles, currentFiles.toSlice())
    Swag.assert(keyFiles.form.rows.count == 1)
    Swag.assert(keyFiles.form.rows[0].field == cast(*Wnd, keyFileFields))
    Swag.assert(keyFileFields.samePaths(currentFiles.toSlice()))
    openAndDismiss(&host, keyFiles)
}

// Opens `dialog`, backs straight out of it, and reports that the box really came up.
//
// Nothing here answers the form: what has to run is the box itself, because that is what measures
// the surface against the fields it was given.
func openAndDismiss(host: *Testing.HeadlessHost, dialog: *FormDlg)
{
    host.clickModalButtonWhenShown(Dialog.BtnCancel)
    let modalResult = dialog.doModal()
    Swag.assert(modalResult == Dialog.BtnCancel)
    Swag.assert(host.autoHandled)
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
    defer discard catch g_App.setLanguage(ReferenceLanguage)

    func assertFormFits(host: *Testing.HeadlessHost, dialog: *FormDlg)
    {
        openAndDismiss(host, dialog)
        let form   = dialog.form
        let needed = form.measure(Math.Point{form.position.width, 0}).preferred.y
        if needed > form.position.height + 0.5
        {
            Console.println("form does not end inside its box: needs ", needed, ", box holds ", form.position.height)
            Swag.assert(false)
        }
    }

    for &one in languages()
    {
        expect g_App.setLanguage(one.tag)
        host.notify(.LanguageChanged)

        var options: FormDlgOptions

        let change = FormDlg.create(&host.surface, options)
        discard buildPasswordChangeForm(change)
        assertFormFits(&host, change)

        let resize = FormDlg.create(&host.surface, options)
        discard buildVaultResizeForm(resize)
        assertFormFits(&host, resize)

        var currentFiles: Array'String
        currentFiles.add("C:\\keys\\first.key")
        let keyFiles = FormDlg.create(&host.surface, options)
        discard buildKeyFileChangeForm(keyFiles, currentFiles.toSlice())
        assertFormFits(&host, keyFiles)

        options.title = appStrings().ui_CreateHidden
        let hidden = FormDlg.create(&host.surface, options)
        discard buildHiddenCreateForm(hidden)
        assertFormFits(&host, hidden)

        options.title = appStrings().ui_ProtectHidden
        let protection = FormDlg.create(&host.surface, options)
        discard buildHiddenProtectionForm(protection)
        assertFormFits(&host, protection)
    }
}

// A mounted vault stands on its own ground with its actions; a locked one says where it is.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    fillPictureList(window)
    Swag.assert(window.list.rows.count == 3)

    let mounted = window.list.rows[0]
    Swag.assert(mounted.open.isLocallyVisible() and mounted.unmount.isLocallyVisible())
    Swag.assert(mounted.unmount.position.right() <= mounted.position.width - RowOutset + 0.5)
    Swag.assert(not window.list.rows[1].open.isLocallyVisible())
    Swag.assert(window.vaultIdentity("C:\\Users\\vault\\papiers.bin") == "mounted on P: · 2 GiB · read and write")
    Swag.assert(Utf8.endsWith(window.vaultIdentity("E:\\archives-2025.bin"), "locked"))

    // The rows stand under the title, one under the other, in the order of the list.
    Swag.assert(window.list.rows[0].position.y > window.list.title.position.bottom())
    Swag.assert(window.list.rows[1].position.y >= window.list.rows[0].position.bottom())

    // Unfolding a locked vault lays the card over its row and the others recede.
    window.chooseVault("C:\\vault.bin")
    Swag.assert(window.list.card.panel.isLocallyVisible())
    Swag.assert(not window.list.rows[1].isLocallyVisible())
    Swag.assert(window.list.card.panel.position.y == window.list.rows[1].position.y)
    Swag.assert(window.list.rows[2].position.y >= window.list.card.panel.position.bottom())

    // Choosing the mounted one folds the card: a mounted vault has nothing to unlock.
    window.chooseVault("C:\\Users\\vault\\papiers.bin")
    Swag.assert(not window.list.card.panel.isLocallyVisible())
}

// The card opens its height over the place of its vault while the rows below follow it, and
// closes back to a row when the vault folds; the keyboard is on the password at once.
#[Swag.TestTag("animation.vault")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    fillPictureList(window)
    host.setReducedMotion(false)
    host.settleAnimations(window)

    let list  = window.list
    let below = list.rows[2]
    window.chooseVault("C:\\vault.bin")
    Swag.assert(window.mountPassword.hasFocus())
    let open = list.card.measureHeight(list.rowWidth())
    host.advanceAnimations(0.05)
    Swag.assert(list.openHeight > VaultRow.Height and list.openHeight < open)
    Swag.assert(Math.abs(list.card.panel.position.height - list.openHeight) < 0.5)
    Swag.assert(Math.abs(below.position.y - (list.card.panel.position.y + list.openHeight + VaultList.RowGap)) < 0.5)
    host.app.animator.finishAll()
    Swag.assert(list.openHeight == open)

    window.foldVault()
    host.advanceAnimations(0.05)
    Swag.assert(list.openHeight > VaultRow.Height and list.openHeight < open)
    Swag.assert(Math.abs(below.position.y - (list.rows[1].position.y + list.openHeight + VaultList.RowGap)) < 0.5)
    host.app.animator.finishAll()
    Swag.assert(list.openPath.isEmpty())
    Swag.assert(Math.abs(below.position.y - (list.rows[1].position.bottom() + VaultList.RowGap)) < 0.5)
}

// A protected startup vault unfolds in the list for its access, on the drive and the read-only
// choice it was marked with. Leaving it skips it and brings up the next one; a reader who chose
// another vault keeps it.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    useTestDestination(window)
    window.privacyMode = false
    window.applyPrivacyControl()

    let folder = Env.getSpecialDirectory(.Temp)
    let first  = Path.combine(folder.toString(), "swagvault_startup_first.bin")
    let second = Path.combine(folder.toString(), "swagvault_startup_second.bin")
    let third  = Path.combine(folder.toString(), "swagvault_startup_third.bin")
    discard expect File.writeAllText(first, "container")
    discard expect File.writeAllText(second, "container")
    discard expect File.writeAllText(third, "container")
    defer
    {
        discard catch File.delete(first)
        discard catch File.delete(second)
        discard catch File.delete(third)
    }

    window.startupQueue.add(StartupVault{first, "D:", true, true, false})
    window.startupQueue.add(StartupVault{second, "D:", true, false, false})
    window.startupQueue.add(StartupVault{third, "D:", true, false, false})
    window.pumpStartupQueue()
    Swag.assert(window.operation.kind == .None)
    Swag.assert(window.chosenLockedPath() == first.toString() and window.startupWaiting == first)
    Swag.assert(window.readOnly.isChecked() and window.selectedMountPoint() == "D:")
    Swag.assert(window.list.card.panel.isLocallyVisible())

    window.foldVault()
    Swag.assert(window.chosenLockedPath() == second.toString() and window.startupWaiting == second)
    Swag.assert(not window.readOnly.isChecked())

    window.chooseVault(first)
    Swag.assert(window.chosenLockedPath() == first.toString() and window.startupQueue.isEmpty())
}

// Marking a mounted vault puts it in the list Swag Vault mounts at its next start, and unmarking
// it takes it back out. Unmounting the drive afterwards leaves the mark alone.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    window.privacyMode = false
    window.applyPrivacyControl()

    window.mountedDrives.drives.add(MountedDrive{null, "C:\\one", "mount-x", "X:", true, false, false, 0, 0})
    window.addVault("C:\\one")
    window.chooseVault("C:\\one")

    discard window.runCommand(VaultCommands.AtStartup)
    Swag.assert(window.startupVaults.count == 1)
    Swag.assert(window.startupVaults[0].path == "C:\\one")
    Swag.assert(window.startupVaults[0].drive == "mount-x")
    Swag.assert(window.startupVaults[0].needsPassword)
    Swag.assert(Utf8.endsWith(window.vaultIdentity("C:\\one"), appStrings().ui_StateAtStartup))

    discard window.mountedDrives.detach(0)
    Swag.assert(window.startupVaults.count == 1)
    Swag.assert(Utf8.endsWith(window.vaultIdentity("C:\\one"), appStrings().ui_StateAtStartup))

    window.mountedDrives.drives.add(MountedDrive{null, "C:\\one", "mount-x", "X:", true, false, true, 0, 0})
    discard window.runCommand(VaultCommands.AtStartup)
    Swag.assert(window.startupVaults.isEmpty())

    // Forgetting a vault takes its mark with it.
    window.mountedDrives.drives.clear()
    window.startupVaults.add(StartupVault{"C:\\one", "mount-x", true, false})
    window.forgetVault("C:\\one")
    Swag.assert(window.startupVaults.isEmpty() and window.vaults.isEmpty())
}

// A capacity is read back the way a reader wrote it, and refused when it says nothing.
#test
{
    var host: Testing.HeadlessHost
    discard testSetupMainWindow(&host)

    Swag.assert(capacityText(256 * 1024 * 1024) == "256 MiB")
    Swag.assert(capacityText(2 * 1024 * 1024 * 1024) == "2 GiB")

    // A size that is not a whole gibibyte stays in mebibytes rather than growing a decimal.
    Swag.assert(capacityText(1536 * 1024 * 1024) == "1536 MiB")

    Swag.assert(parseCapacity("256", 0).bytes == 256 * 1024 * 1024)
    Swag.assert(parseCapacity("2", 1).bytes == 2 * 1024 * 1024 * 1024)
    Swag.assert(not parseCapacity("", 0).error.isEmpty())
    Swag.assert(not parseCapacity("0", 0).error.isEmpty())
    Swag.assert(not parseCapacity("12x", 0).error.isEmpty())
    Swag.assert(not parseCapacity("18446744073709551615", 1).error.isEmpty())
}

// The creation dialog preserves the exact filename; a vault has no required extension.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    let path = Testing.tempFilePath("vault-vault-", "")
    host.acceptModalFileDialog(path)
    window.chooseContainer(window.createPath, true)

    Swag.assert(host.autoHandled)
    Swag.assert(path == window.createPath.text())
}

// Opening a file puts its vault on the list, unfolded. Privacy keeps browse history off disk, but
// the open dialog still returns to its last folder while this process is running.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    let path = Testing.tempFilePath("vault-open-state-", ".vault")
    defer discard catch File.delete(path)
    discard expect File.writeAllBytes(path, [1'u8])

    host.acceptModalFileDialog(path)
    window.openVaultFile()

    Swag.assert(host.autoHandled)
    Swag.assert(window.chosenPath == path and window.vaults.count == 1)
    Swag.assert(window.list.card.panel.isLocallyVisible())
    Swag.assert(Path.equals(window.fileDlgState.currentFolder, Path.directoryName(path) orelse ""))

    host.clickModalButtonWhenShown(Dialog.BtnCancel)
    window.openVaultFile()
    Swag.assert(host.autoHandled)
    Swag.assert(Path.equals(window.fileDlgState.currentFolder, Path.directoryName(path) orelse ""))
}

// The key-file field can add an existing key file, generate a cryptographically random one, and
// remove either selection without storing the paths anywhere else.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    let field  = KeyFileField.create(window)

    let existing = Testing.tempFilePath("vault-key-existing-", ".key")
    defer discard catch File.delete(existing)
    discard expect File.writeAllBytes(existing, [1'u8, 2, 3])

    host.acceptModalFileDialog(existing)
    field.add.sigPressed.call(cast(*Button, field.add))
    Swag.assert(host.autoHandled)
    Swag.assert(field.paths.count == 1)
    Swag.assert(field.paths[0] == existing)

    let generated = Testing.tempFilePath("vault-key-random-", ".key")
    defer discard catch File.delete(generated)
    host.acceptModalFileDialog(generated)
    field.generate.sigPressed.call(cast(*Button, field.generate))
    Swag.assert(host.autoHandled)
    Swag.assert(field.paths.count == 2)
    Swag.assert((expect File.info(generated)).size == 64)

    field.files.setSelectedIndex(0, notify: false)
    field.remove.sigPressed.call(cast(*Button, field.remove))
    Swag.assert(field.paths.count == 1)
    Swag.assert(field.paths[0] == generated)
}

// A container dropped on the location field fills it, exactly as browsing to it would.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    window.showPage(.Create, animate: false)
    Swag.assert(host.dropFilesOnWnd(window.createPath, ["c:/vaults/private"]) == DropEffect.Copy)
    Swag.assert(window.createPath.text() == "c:/vaults/private")

    // Filling the field is what makes the action live, whether a dialog or a drop wrote it.
    Swag.assert(window.createButton.isEnabled())
}

// A container dropped anywhere else on the window joins the list, unfolded and ready for its access.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    window.showPage(.Options, animate: false)
    Swag.assert(host.dropFilesOnWnd(window, ["c:/vaults/private"]) == DropEffect.Copy)

    Swag.assert(window.page == .List)
    Swag.assert(window.chosenPath == "c:/vaults/private")
    Swag.assert(window.mountPassword.hasFocus())
}

// A filename extension never decides whether a dropped file is a container.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    Swag.assert(host.dropFilesOnWnd(window, ["c:/vaults/private.anything"]) == DropEffect.Copy)
    Swag.assert(window.chosenPath == "c:/vaults/private.anything")

    // Two files name no single vault to open.
    window.foldVault()
    Swag.assert(host.dropFilesOnWnd(window, ["c:/vaults/a", "c:/vaults/b"]) == DropEffect.None)
    Swag.assert(window.chosenPath.isEmpty() and window.vaults.isEmpty())
}

// A saved startup choice asks for hidden access again; neither its bytes nor the protection of a
// next mount become ordinary saved settings.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    window.privacyMode = false
    window.startupVaults.add(StartupVault{"C:\\vault.bin", "mount-x", true, false, true})
    var keyFiles: Array'String
    window.operation.hiddenAccess.setInputs("private hidden credentials", keyFiles.toSlice())
    window.protectHiddenOnMount = true
    let state = saveMainWindowState(window)
    Swag.assert(not containsStateBytes(state.toSlice(), "private hidden credentials"))
    window.startupVaults.clear()
    window.protectHiddenOnMount = false
    loadMainWindowState(window, state.toSlice())
    Swag.assert(window.startupVaults.count == 1 and window.startupVaults[0].protectHidden)
    Swag.assert(not window.protectHiddenOnMount)
}

// Renders the window as it stands, in Encre or in Papier, and compares it with the golden `name`.
//
// The chrome is not part of what these images pin: a headless surface has no desktop under it, so
// its shadow falls on nothing and its rounded corner only punches holes in the captured pixels.
// Applying a palette puts the geometry of that palette back, so it is squared again here.
func assertSurfaceGolden(host: *Testing.HeadlessHost, window: *MainWindow, dark: bool, name: string)
{
    if dark do
        host.theme.setDark()
    else do
        host.theme.setLight()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    window.applyLayout()
    host.settleAnimations(window, 6)

    var image = host.render(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&image, Format.toString("%.%", name, dark ? "encre" : "papier"))
}

// What the list looks like, against `vault.list`: a title, one vault mounted on its own ground
// with its actions, two at rest, the two quiet words, and the hint line. One host per palette:
// a render target keeps what the last paint left.
#[Swag.TestTag("golden")]
#test
{
    for dark in [true, false]
    {
        var host: Testing.HeadlessHost
        let window = testSetupMainWindow(&host)
        fillPictureList(window)
        assertSurfaceGolden(&host, window, dark, "list")
    }
}

// A locked vault unfolded in place, against `vault.unlock.paper`.
#[Swag.TestTag("golden")]
#test
{
    for dark in [true, false]
    {
        var host: Testing.HeadlessHost
        let window = testSetupMainWindow(&host)
        fillPictureList(window)
        window.chooseVault("C:\\vault.bin")
        assertSurfaceGolden(&host, window, dark, "unlock")
    }
}

// The page that creates a vault, against `vault.create.paper`.
#[Swag.TestTag("golden")]
#test
{
    for dark in [true, false]
    {
        var host: Testing.HeadlessHost
        let window = testSetupMainWindow(&host)
        window.showPage(.Create, animate: false)
        window.createPath.setText("C:\\Users\\vault\\Documents\\papiers.bin")

        // The room left on a volume belongs to the machine, so the picture states it.
        window.createPage.showFreeSpace(212'u64 * 1024 * 1024 * 1024, "C:\\")
        assertSurfaceGolden(&host, window, dark, "create")
    }
}

// The randomisation of a new container, against `vault.progress`.
#[Swag.TestTag("golden")]
#test
{
    for dark in [true, false]
    {
        var host: Testing.HeadlessHost
        let window = testSetupMainWindow(&host)
        let texts  = appStrings()
        window.progressPage.begin("C:\\Users\\vault\\papiers.bin", texts.ui_Randomizing, texts.ui_RandomizeHelp, texts.ui_StopCreating)
        window.progressPage.setProgress(0.62, 159 * 1024 * 1024, 256 * 1024 * 1024, Format.toString(texts.ui_SecondsLeft, 12))
        window.showPage(.Progress, animate: false)
        assertSurfaceGolden(&host, window, dark, "progress")
    }
}

// The privacy page, against `vault.options`.
#[Swag.TestTag("golden")]
#test
{
    for dark in [true, false]
    {
        var host: Testing.HeadlessHost
        let window = testSetupMainWindow(&host)
        window.showPage(.Options, animate: false)
        assertSurfaceGolden(&host, window, dark, "options")
    }
}
