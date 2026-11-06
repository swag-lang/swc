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
        Swag.require(firstError != null and not isCanceledError(firstError))
        firstMessage = caughtMessage(firstError)
        Swag.require(firstMessage == expectedFirst)
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
        Swag.require(canceledError != null and isCanceledError(canceledError))
        let message = caughtMessage(canceledError)
        Swag.require(message == appStrings().msg_OperationStopped)
    }

    Swag.require(firstMessage == expectedFirst)
    Swag.require(not File.exists(path))

    window.operation.error.reset()
    window.operation.kind = .Unmount
    window.operation.task.submit(func|window|() { window.runOperation() })
    window.operation.task.wait()
    Swag.require(window.operation.error.isEmpty())
    window.operation.kind = .None
}

// Builds the real main window, at its smallest size, inside the frame of the shipped surface.
internal func testSetupMainWindow(host: *Testing.HeadlessHost, scale = 1.0'f32, width = cast(f32, MainWindow.MinWidth), height = cast(f32, MainWindow.MinHeight))->*MainWindow
{
    host.setup(width, height, scale)
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
internal func useTestDestination(window: *MainWindow)
{
    window.mountDestinations.clear()
    window.mountDestinations.add(MountDestination{"D:", "D:"})
    window.drive.clear()
    window.drive.addItem("D:")
    window.drive.setSelectedIndex(0, notify: false)
}

// Fills the list the way the charter pictures it: one vault mounted, two at rest.
internal func fillPictureList(window: *MainWindow)
{
    useTestDestination(window)
    window.privacyMode = false
    window.applyPrivacyControl()
    window.vaults.add(KnownVault{"C:\\Users\\vault\\papiers.bin", "D:", false})
    window.vaults.add(KnownVault{"C:\\vault.bin", "D:", false})
    window.vaults.add(KnownVault{"E:\\archives-2025.bin", "D:", false})
    window.mountedDrives.drives.add(MountedDrive{null, "C:\\Users\\vault\\papiers.bin", "P:", "P:", true, false, false, 2 * 1024 * 1024 * 1024, 780 * 1024 * 1024})
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
        Swag.require(false)
    }
}

// The window is built in the reference language, on the list, whatever the language of the account.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    Swag.require(activeLanguage() == ReferenceLanguage)
    Swag.require(window.page == .List)
    Swag.require(window.list.title.text() == "Vaults")
    Swag.require(window.createButton.text() == "Create Encrypted Vault")
    Swag.require(window.language == ReferenceLanguage)

    // The appearance action keeps the choice and its persistence, and draws nothing: the theme,
    // the language and About are lens entries.
    Swag.require(window.appearanceButton.parent == &host.surfaceWnd)
    Swag.require(not window.appearanceButton.isLocallyVisible())

    window.themeIndex = cast(u32, AppearanceTheme.Dark)
    window.applyTheme()
    Swag.require(window.appearanceButton.appearanceTheme == .Dark and host.theme.colors.ground == ThemeColors.encrePalette().ground)
    window.themeIndex = cast(u32, AppearanceTheme.Light)
    window.applyTheme()
    Swag.require(window.appearanceButton.appearanceTheme == .Light and host.theme.colors.ground == ThemeColors.papierPalette().ground)
    window.themeIndex = cast(u32, AppearanceTheme.System)
    window.applyTheme()
    Swag.require(window.appearanceButton.appearanceTheme == .System and host.theme.colors.ground == ThemeColors.encrePalette().ground)
}

// Privacy is the default: no vault path reaches the state, and the list keeps only what is
// mounted or being unlocked.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    Swag.require(window.privacyMode)
    Swag.require(not window.protectHiddenOnMount)
    Swag.require(window.privacyModeControl.isChecked())

    window.openVault("C:\\private\\unlisted")
    Swag.require(window.vaults.count == 1 and window.chosenPath == "C:\\private\\unlisted")
    window.startupVaults.add(StartupVault{"C:\\private\\startup", "mount-x", true, false})
    window.fileDlgState.currentFolder = "C:\\private\\browse-private"
    var state = saveMainWindowState(window)
    Swag.require(not containsStateBytes(state.toSlice(), "unlisted"))
    Swag.require(not containsStateBytes(state.toSlice(), "startup"))
    Swag.require(not containsStateBytes(state.toSlice(), "browse-private"))

    // Folded, a locked vault leaves the list at once.
    window.foldVault()
    Swag.require(window.vaults.isEmpty())
    Swag.require(window.list.rows.isEmpty())

    window.clearPrivateState()
    Swag.require(window.startupVaults.isEmpty())
}

// About is a lens entry, and reaches the standard application box.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    Swag.require(not window.appearanceButton.sigAboutRequested.isEmpty())
    host.clickModalButtonWhenShown(Dialog.BtnCancel)
    window.showAbout()
    host.pump()

    Swag.require(host.autoHandled)
    Swag.require(host.openedSurfaceCount() == 0)
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
            Swag.require(card.panel.isLocallyVisible())
            Swag.require(card.form.position.bottom() <= card.options.position.y + 0.5)
            Swag.require(card.mount.position.bottom() <= card.panel.position.height + 0.5)
            for child in card.options.children where child.isLocallyVisible() do
                Swag.require(card.options.position.x + child.position.right() <= card.mount.position.x + 0.5)

            window.showPage(.Create, animate: false)
            Testing.assertContentFits(window)
            assertColumnFits(window, window.createPage, window.createPage.column)
            let create = window.createPage
            Swag.require(create.cancel.position.right() <= create.createAction.position.x)
            Swag.require(create.keyFiles.position.right() <= create.cancel.position.x)

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

// A page change arrives quietly: the incoming page fades in from its side without choosing focus.
#[Swag.TestTag("animation.vault")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    host.setReducedMotion(false)
    host.settleAnimations(window)

    window.showPage(.Create)
    Swag.require(window.focusedWindow() == null)
    host.advanceAnimations(0.05)
    Swag.require(window.createPage.presentationOpacity > 0 and window.createPage.presentationOpacity < 1)
    host.app.animator.finishAll()
    Swag.require(window.createPage.presentationOpacity == 1)
    Swag.require(not window.list.scroll.isLocallyVisible())
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

    Swag.require(window.list.title.text() == "Coffres")
    Swag.require(row.unmount.text() == "Démonter")
    Swag.require(row.open.text() == "P:" and row.open.toolTip == "Ouvrir P:")
    Swag.require(window.createButton.text() == "Créer le coffre chiffré")
    Swag.require(window.mountButton.text() == "Monter")
    Swag.require(window.optionsPage.head.title.text() == "Vie privée")
    Swag.require(Utf8.startsWith(window.vaultIdentity("C:\\Users\\vault\\papiers.bin"), "monté sur P:"))

    expect window.appearanceButton.setAppearanceLanguage(ReferenceLanguage, notify: true)
    host.notify(.LanguageChanged)
    Swag.require(row.unmount.text() == "Unmount")
}

// Picking a language remembers it, and the system entry restores "follow the account".
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer discard catch g_App.setLanguage(ReferenceLanguage)

    // The window opens on the reference language rather than on the account.
    Swag.require(window.appearanceButton.language == ReferenceLanguage)

    expect window.appearanceButton.setAppearanceLanguage("fr", notify: true)
    host.notify(.LanguageChanged)
    Swag.require(window.language == "fr")
    Swag.require(activeLanguage() == "fr")
    Swag.require(window.appearanceButton.language == "fr")

    expect window.appearanceButton.setAppearanceLanguage("", notify: true)
    Swag.require(window.language.isEmpty())
    Swag.require(activeLanguage() == systemLanguage())
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
    Swag.require(window.vaults.count == 1)
    Swag.require(window.vaults[0].drive == "D:" and window.vaults[0].readOnly)

    // Put unmistakable bytes in the password storage. Persistent state must never observe them.
    let secret = "not a setting"
    Swag.memcpy(&window.mountPassword.storage[0], secret.buffer, secret.count)
    window.mountPassword.byteCount = secret.count

    var state       = saveMainWindowState(window)
    let secretBytes = cast(const [..] u8, secret)
    Swag.require(not containsStateBytes(state.toSlice(), secretBytes))

    window.unlockKeyFiles.add("C:\\private\\access.key")
    state = saveMainWindowState(window)
    Swag.require(not containsStateBytes(state.toSlice(), "access.key"))

    window.mountedDrives.drives.clear()
    window.vaults.clear()
    window.forgetAccess()
    loadMainWindowState(window, state.toSlice())

    Swag.require(window.vaults.count == 1)
    Swag.require(window.vaults[0].path == "C:\\vaults\\remembered")
    Swag.require(window.vaults[0].drive == "D:" and window.vaults[0].readOnly)
    Swag.require(window.mountPassword.isEmpty())
    Swag.require(window.unlockKeyFiles.isEmpty())

    // Choosing it again starts from the choices of its last mount.
    window.chooseVault("C:\\vaults\\remembered")
    Swag.require(window.readOnly.isChecked())
    Swag.require(window.selectedMountPoint() == "D:")
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
    Swag.require(window.vaults.count == 1 and
                 window.vaults[0].path == "C:\\vaults\\legacy" and
                 window.vaults[0].readOnly)
}

// Automatic-unmount choices are explicit persistent policy, and the timeout is only actionable
// while inactivity handling is enabled.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    Swag.require(window.unmountOnLock.isChecked())
    Swag.require(window.unmountOnSuspend.isChecked())
    Swag.require(not window.unmountOnIdle.isChecked())
    Swag.require(not window.idleTimeout.isEnabled())

    window.unmountOnLock.toggle()
    window.unmountOnIdle.toggle()
    window.optionsPage.setTimeout(2)
    window.readAutoUnmountControls()
    var state = saveMainWindowState(window)

    window.autoUnmount = {}
    window.applyAutoUnmountControls()
    loadMainWindowState(window, state.toSlice())

    Swag.require(not window.autoUnmount.onSessionLock)
    Swag.require(window.autoUnmount.onSuspend)
    Swag.require(window.autoUnmount.onIdle)
    Swag.require(window.autoUnmount.idleMinutes == 30)
    Swag.require(window.idleTimeout.isEnabled())

    // The switches are lens entries too, and the lens says which are on.
    discard window.runCommand(VaultCommands.UnmountOnSuspend)
    Swag.require(not window.autoUnmount.onSuspend)
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

    Swag.require(window.mountedDrives.drives.count == 1)
    Swag.require(window.mountedDrives.drives[0].path == "C:\\open")
    Swag.require(window.statusMessage == .AutoUnmounted)

    // With privacy mode on, the closed vault leaves the list with its drive.
    Swag.require(window.vaults.count == 1 and window.list.rows.count == 1)

    window.autoUnmount.onSessionLock = false
    window.mountedDrives.drives.add(MountedDrive{null, "C:\\second", "mount-z", "Z:", true, false, false, 0, 0})
    window.handleAutoUnmount(.SessionLock)
    Swag.require(window.mountedDrives.drives.count == 2)
}

// A page begins without focus. Choosing a locked vault places the keyboard in its password,
// and Tab walks the access choices in reading order.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    useTestDestination(window)

    Swag.require(window.focusedWindow() == null)

    // The lens opened from the neutral list returns there. Its focused input disappearing must
    // not nominate the first quiet link and leave New Vault ringed.
    host.keyPress(Input.Key.Space, .Control)
    Swag.require(window.lens.isOpen())
    Swag.require(window.focusedWindow() != null)
    host.keyPress(Input.Key.Escape)
    Swag.require(not window.lens.isOpen())
    Swag.require(window.focusedWindow() == null)
    host.pump()
    Swag.require(window.focusedWindow() == null)
    Swag.require(not window.list.newVault.showsFocusRing())

    window.openVault("C:\\vaults\\one")
    Swag.require(window.mountPassword.hasFocus())
    Swag.require(window.mountButton.isEnabled())
    host.keyPress(Input.Key.Tab)
    Swag.require(window.drive.hasFocus())
    host.keyPress(Input.Key.Tab)
    Swag.require(window.list.card.keyFiles.hasFocus())
    host.keyPress(Input.Key.Tab)
    Swag.require(window.readOnly.hasFocus())
    host.keyPress(Input.Key.Tab)
    Swag.require(window.mountButton.hasFocus())

    // Escape folds the vault, and the keyboard goes back to the list.
    window.readOnly.setFocus()
    host.keyPress(Input.Key.Escape)
    Swag.require(window.chosenPath.isEmpty())
    Swag.require(not window.list.card.panel.isLocallyVisible())

    // Opening the create form leaves focus clear; editing its first field starts the keyboard path.
    window.showPage(.Create, animate: false)
    Swag.require(window.focusedWindow() == null)
    window.createPath.setFocus()
    Swag.require(window.createPath.hasFocus())
    host.keyPress(Input.Key.Tab)
    Swag.require(window.browseCreate.hasFocus())
    host.keyPress(Input.Key.Escape)
    Swag.require(window.page == .List)
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
    Swag.require(window.focusedWindow() == null)
    window.createPath.setFocus()
    Swag.require(window.createPath.hasFocus())
    host.keyPress(Input.Key.Tab)
    Swag.require(window.browseCreate.hasFocus())

    // The box runs a nested loop, so the way out is armed before it opens. Escape first leaves
    // the path field and then reaches the cancel action. A box that
    // does not answer it is closed by hand after a few frames, so this fails on its assertion
    // rather than pumping frames until the runner gives up on it.
    var frames = 0's32
    var forced: bool
    host.app.sigFrame += func|host = &host, window, frames = &frames, forced = &forced|(app)
    {
        if not host.openedSurfaceCount() do
            return

        frames[] += 1
        if frames[] <= 2
        {
            let focused = unwrap window.focusedWindow()
            Swag.require(focused.surface != window.surface, "dialog did not take keyboard focus")
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
    Swag.require(frames != 0)
    Swag.require(not forced)
    Swag.require(host.openedSurfaceCount() == 0)

    // Nothing was chosen, the page is still up, and the keyboard is back where it was.
    Swag.require((window.createPath.text()).count == 0)
    Swag.require(window.page == .Create)
    Swag.require(window.browseCreate.hasFocus())
}

// The notice line is named, not written, so it says the same thing in the new language; with
// nothing to say, it is not there.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer discard catch g_App.setLanguage(ReferenceLanguage)

    Swag.require(window.statusText() == "Ready — create a vault or choose one to open.")
    Swag.require(not window.list.notice.isLocallyVisible())

    window.statusDrive = "Z:"
    window.setStatus(.Mounted)
    Swag.require(Utf8.contains(window.statusText(), "Z:"))
    Swag.require(window.list.notice.isLocallyVisible())

    expect g_App.setLanguage("fr")
    Swag.require(Utf8.startsWith(window.statusText(), "Lecteur chiffré monté sur Z:"))
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
    Swag.require(messageFor(.PasswordOrDamaged) == "The password or key files are incorrect, or the container is damaged.")
    Swag.require(messageFor(.Corrupted) == "The container is damaged.")
    Swag.require(messageFor(.PasswordRequired) == "A password is required.")
    Swag.require(messageFor(.Canceled) == "The operation stopped.")
    Swag.require(messageFor(.General) == appStrings().msg_SystemError)

    // Every way a container can refuse to open answers the same sentence: telling wrong access
    // from a damaged container is exactly what the format refuses to do.
    Swag.require(messageFor(.PasswordOrDamaged) != messageFor(.Corrupted))

    expect g_App.setLanguage("fr")
    Swag.require(messageFor(.PasswordOrDamaged) == "Le mot de passe ou les fichiers clés sont incorrects, ou le conteneur est endommagé.")
    Swag.require(messageFor(.PasswordRequired) == appStrings().msg_PasswordRequired)
    Swag.require(messageFor(.DiskFull) == appStrings().msg_ErrDiskFull)
    Swag.require(messageFor(.General) == appStrings().msg_SystemError)

    // A kind that means nothing to a reader reads as the generic damaged-container wording.
    Swag.require(messageFor(.DirectoryNotEmpty) == appStrings().msg_ErrDamaged)
    Swag.require(messageFor(.NotDirectory) == appStrings().msg_ErrDamaged)
}

// A form with no password in it is a form that can act: an empty password is a vault that
// opens without one, not a field left blank.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    useTestDestination(window)

    Swag.require(not window.canCreate())
    Swag.require(not window.createButton.isEnabled())
    window.createPath.setText("C:\\open")
    Swag.require(window.canCreate())
    Swag.require(window.createButton.isEnabled())

    // A vault the list unfolds can be mounted and changed with nothing else typed.
    Swag.require(not window.canModifyVault())
    window.openVault("C:\\open")
    Swag.require(window.canModifyVault())
    Swag.require(window.canMount())
    Swag.require(window.mountButton.isEnabled())
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
    Swag.require(not window.lensLauncher.captionButton.isLocallyVisible())
    let commandIds = [VaultCommands.NewVault, VaultCommands.OpenFile, VaultCommands.Vaults, VaultCommands.Options,
                      VaultCommands.Mount, VaultCommands.Unmount, VaultCommands.OpenDrive, VaultCommands.ReadOnly,
                      VaultCommands.ProtectHidden, VaultCommands.AtStartup, VaultCommands.ChangePassword,
                      VaultCommands.ChangeKeyFiles, VaultCommands.Resize, VaultCommands.CreateHidden,
                      VaultCommands.Forget, VaultCommands.Stop, VaultCommands.PrivacyMode,
                      VaultCommands.UnmountOnLock, VaultCommands.UnmountOnSuspend, VaultCommands.UnmountOnIdle]
    for id in commandIds
    {
        let state = window.sendComputeCommandStateEvent(id)
        Swag.require(state.updatedFields.has(.Icon) and state.icon.isValid())
    }

    window.openVault("C:\\vaults\\locked")
    window.lens.open(">")
    for title in [texts.ui_NewVault, texts.ui_OpenFile, texts.ui_VaultsTitle, texts.cmd_Options,
                  texts.ui_Mount, texts.ui_ReadOnly, texts.ui_ProtectHidden, texts.ui_ChangePassword,
                  texts.ui_ChangeKeyFiles, texts.ui_Resize, texts.ui_CreateHidden, texts.ui_Forget,
                  texts.ui_PrivacyMode, texts.ui_UnmountOnLock, texts.ui_UnmountOnSuspend, texts.ui_UnmountOnIdle] do
        Swag.require(lensHasEntry(window, title))
    window.lens.close()

    // A mounted vault offers what applies to a drive instead.
    window.mountedDrives.drives.add(MountedDrive{null, "C:\\vaults\\locked", "D:", "X:", true, false, false, 0, 0})
    window.refreshVaults()
    window.lens.open(">")
    Swag.require(lensHasEntry(window, texts.ui_Unmount))
    Swag.require(lensHasEntry(window, Format.toString(texts.ui_OpenDrive, "X:")))
    Swag.require(lensHasEntry(window, texts.ui_MountAtStartup))
    Swag.require(not lensHasEntry(window, texts.ui_Mount))
    window.lens.close()

    // At rest the lens keeps file actions first, then what the chosen vault can do under its name, and
    // another vault.
    window.lens.open()
    Swag.require(window.lens.results.sections[0]!.label == texts.lens_File and window.lens.results.sections[1]!.label == "locked")
    Swag.require(lensHasEntry(window, texts.ui_Unmount) and lensHasEntry(window, Format.toString(texts.ui_OpenDrive, "X:")))
    Swag.require(lensHasEntry(window, texts.ui_NewVault) and lensHasEntry(window, texts.ui_OpenFile))
    Swag.require(not lensHasEntry(window, texts.ui_MountAtStartup) and not lensHasEntry(window, texts.ui_Mount))
    window.lens.close()

    // The vaults answer a query by name.
    window.addVault("C:\\vaults\\other.bin")
    window.lens.open("other")
    Swag.require(lensHasEntry(window, "other.bin"))
    window.lens.close()

    // Protecting the hidden volume is a choice of the next mount, said on the vault's line.
    window.chooseVault("C:\\vaults\\other.bin")
    discard window.runCommand(VaultCommands.ProtectHidden)
    Swag.require(window.protectHiddenOnMount)
    Swag.require(Utf8.contains(window.vaultIdentity("C:\\vaults\\other.bin"), texts.ui_StateProtected))
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

    Swag.require(change.form.rows.count == 2)
    Swag.require(change.form.rows[0].field == cast(*Wnd, fields.replacement))
    Swag.require(change.form.rows[0].label.name.raw == texts.ui_NewPassword)
    Swag.require(change.form.rows[1].field == cast(*Wnd, fields.confirm))
    openAndDismiss(&host, change)

    let resize       = FormDlg.create(&host.surface, options)
    let resizeFields = buildVaultResizeForm(resize)

    Swag.require(resize.form.rows.count == 2)
    Swag.require(resize.form.rows[0].field == cast(*Wnd, resizeFields.capacity))
    Swag.require(resize.form.rows[0].label.name.raw == texts.ui_NewCapacity)
    Swag.require(resizeFields.capacity.text() == "256")
    Swag.require(resizeFields.unit.selectedIndex == 0)
    Swag.require(resizeFields.keepCapacity.isChecked())
    Swag.require(not resizeFields.capacity.isEnabled())
    Swag.require(not resizeFields.unit.isEnabled())
    resizeFields.keepCapacity.toggle()
    Swag.require(resizeFields.capacity.isEnabled())
    Swag.require(resizeFields.unit.isEnabled())
    openAndDismiss(&host, resize)

    var currentFiles: Array'String
    currentFiles.add("C:\\keys\\first.key")
    let keyFiles      = FormDlg.create(&host.surface, options)
    let keyFileFields = buildKeyFileChangeForm(keyFiles, currentFiles.toSlice())
    Swag.require(keyFiles.form.rows.count == 1)
    Swag.require(keyFiles.form.rows[0].field == cast(*Wnd, keyFileFields))
    Swag.require(keyFileFields.samePaths(currentFiles.toSlice()))
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
    Swag.require(modalResult == Dialog.BtnCancel)
    Swag.require(host.autoHandled)
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
            Swag.require(false)
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
    Swag.require(window.list.rows.count == 3)

    let mounted = window.list.rows[0]
    Swag.require(mounted.open.isLocallyVisible() and mounted.unmount.isLocallyVisible())
    Swag.require(mounted.unmount.position.right() <= mounted.position.width - RowOutset + 0.5)
    Swag.require(not window.list.rows[1].open.isLocallyVisible())
    Swag.require(window.vaultIdentity("C:\\Users\\vault\\papiers.bin") == "mounted on P: · 2 GiB · read and write")
    Swag.require(Utf8.endsWith(window.vaultIdentity("E:\\archives-2025.bin"), "locked"))

    // In the list, the line under a name leaves out what the row already shows: the drive is the
    // large figure, the room is the thread, the state is the dot and its group.
    Swag.require(window.vaultPlace("C:\\Users\\vault\\papiers.bin", 0) == "C:\\Users\\vault · read and write")
    Swag.require(window.vaultPlace("E:\\archives-2025.bin", 0) == "E:\\")
    Swag.require(window.vaultPlace("E:\\archives-2025.bin", 4 * 1024 * 1024 * 1024) == "E:\\ · 4 GiB")
    Swag.require(mounted.position.height == VaultRow.MountedHeight and window.list.rows[1].position.height == VaultRow.Height)

    // The rows stand under the title, one under the other, in the order of the list.
    Swag.require(window.list.rows[0].position.y > window.list.title.position.bottom())
    Swag.require(window.list.rows[1].position.y >= window.list.rows[0].position.bottom())

    // Unfolding a locked vault lays the card over its row and the others recede.
    window.chooseVault("C:\\vault.bin")
    Swag.require(window.list.card.panel.isLocallyVisible())
    Swag.require(not window.list.rows[1].isLocallyVisible())
    Swag.require(window.list.card.panel.position.y == window.list.rows[1].position.y)
    Swag.require(window.list.rows[2].position.y >= window.list.card.panel.position.bottom())

    // Choosing the mounted one folds the card: a mounted vault has nothing to unlock.
    window.chooseVault("C:\\Users\\vault\\papiers.bin")
    Swag.require(not window.list.card.panel.isLocallyVisible())
}

// The list opens with its title, the two ways to another vault at the end of its line, then the
// vaults in two groups under their labels: the mounted ones first, whatever the order of the list.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    fillPictureList(window)

    // A vault mounted after the others still heads the list.
    window.vaults.removeAtOrdered(0)
    window.vaults.add(KnownVault{"C:\\Users\\vault\\papiers.bin", "D:", false})
    window.refreshVaults()

    let list = window.list
    Swag.require(list.title.isLocallyVisible() and not list.welcome.isLocallyVisible())
    Swag.require(list.rows[0].path == "C:\\Users\\vault\\papiers.bin")
    Swag.require(list.rows[1].path == "C:\\vault.bin" and list.rows[2].path == "E:\\archives-2025.bin")
    Swag.require(list.mountedCount == 1)

    // Beside vaults, both ways are secondary, and they end the title's line on the column's edge.
    Swag.require(list.newVault.form == .Normal and list.openFile.form == .Flat)
    Swag.require(Math.abs(list.newVault.position.right() - list.title.position.right()) < 0.5)
    Swag.require(list.openFile.position.right() < list.newVault.position.x)
    Swag.require(list.newVault.position.y >= list.title.position.y and list.newVault.position.bottom() <= list.title.position.bottom())

    // Each group opens with its label, on the column's edge, above its first row.
    Swag.require(list.mountedHead.x == list.title.position.x)
    Swag.require(list.mountedHead.bottom() <= list.rows[0].position.y)
    Swag.require(list.lockedHead.y >= list.rows[0].position.bottom())
    Swag.require(list.lockedHead.bottom() <= list.rows[1].position.y)

    // Without a mounted vault, the list has one group only.
    window.mountedDrives.drives.clear()
    window.refreshVaults()
    Swag.require(list.mountedCount == 0 and list.mountedHead.width == 0 and list.lockedHead.width > 0)
}

// Without a vault, the page is the home: the mark at its centre, a title and two lines, a new vault
// as its one primary action with opening a file beside it, and a foot under a hairline. The hint
// line teaches the keys of both ways before the lens. In French as in English, it fits.
#test
{
    defer discard catch g_App.setLanguage(ReferenceLanguage)
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    let list   = window.list

    for french in [false, true]
    {
        expect host.app.setLanguage(french ? "fr" : ReferenceLanguage)
        host.notify(.LanguageChanged)
        window.applyLayout()

        // Privacy mode is the default, so the home says why the list is empty.
        let texts = appStrings()
        Swag.require(list.rows.isEmpty())
        Swag.require(not list.title.isLocallyVisible() and
                     list.heading.isLocallyVisible() and
                     list.welcome.isLocallyVisible())
        Swag.require(list.heading.text() == texts.ui_HomeTitlePrivacy)
        let welcome = Format.toString("%\n%", texts.ui_HomeWelcome, texts.ui_HomePrivacy)
        Swag.require(list.welcome.text() == welcome.toString())
        Swag.require(list.newVault.form == .Strong and list.openFile.form == .Normal)

        // The mark, the words, the ways and the hairline stand one under the other, on the page's
        // centre line, above the hint line.
        let center = list.clientRect().horzCenter()
        Swag.require(Math.abs(list.markRect.horzCenter() - center) < 1)
        Swag.require(list.heading.position.y >= list.markRect.bottom())
        Swag.require(list.welcome.position.y >= list.heading.position.bottom())
        Swag.require(list.newVault.position.y >= list.welcome.position.bottom())
        Swag.require(list.newVault.position.right() < list.openFile.position.x)
        Swag.require(Math.abs((list.newVault.position.x + list.openFile.position.right()) * 0.5 - center) < 1)
        Swag.require(list.ruleRect.y > list.openFile.position.bottom())
        Swag.require(Math.abs(list.ruleRect.horzCenter() - center) < 1)
        Swag.require(list.ruleRect.y + VaultList.RuleToFoot + VaultList.FootLineGap < window.hintLine.position.y)
        Testing.assertContentFits(window)

        let hints = window.hintLine.hints
        Swag.require(hints.count == 3)
        Swag.require(hints[0].key == Input.formatKeyShortcut(.Control, .N) and hints[0].text == texts.ui_HintNewVault)
        Swag.require(hints[1].key == Input.formatKeyShortcut(.Control, .O) and hints[1].text == texts.ui_HintOpenFile)
        Swag.require(hints[2].key == Input.formatKeyShortcut(.Control, .Space))

        // A hint line too long for the window would drop its last hints, the lens's first.
        Swag.require(window.hintLine.contentWidth() <= window.clientRect().width - 2 * PageGutter)
    }

    // With privacy mode off, the home says what a vault keeps.
    window.privacyMode = false
    window.applyPrivacyControl()
    window.refreshVaults()
    Swag.require(list.heading.text() == appStrings().ui_HomeTitle)
    let welcome = Format.toString("%\n%", appStrings().ui_HomeWelcome, appStrings().ui_HomeKeeps)
    Swag.require(list.welcome.text() == welcome.toString())

    // A container dropped on the home is what its foot says: it joins the list, unfolded, and the
    // keys of the home leave the hint line with it.
    Swag.require(host.dropFilesOnWnd(list, ["C:\\vaults\\dropped.bin"]) != DropEffect.None)
    Swag.require(window.chosenPath == "C:\\vaults\\dropped.bin" and list.card.panel.isLocallyVisible())
    window.foldVault()
    Swag.require(list.rows.count == 1 and window.hintLine.hints.count == 1)
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
    Swag.require(window.mountPassword.hasFocus())
    let open = list.card.measureHeight(list.rowWidth())
    host.advanceAnimations(0.05)
    Swag.require(list.openHeight > VaultRow.Height and list.openHeight < open)
    Swag.require(Math.abs(list.card.panel.position.height - list.openHeight) < 0.5)
    Swag.require(Math.abs(below.position.y - (list.card.panel.position.y + list.openHeight + VaultList.RowGap)) < 0.5)
    host.app.animator.finishAll()
    Swag.require(list.openHeight == open)

    window.foldVault()
    host.advanceAnimations(0.05)
    Swag.require(list.openHeight > VaultRow.Height and list.openHeight < open)
    Swag.require(Math.abs(below.position.y - (list.rows[1].position.y + list.openHeight + VaultList.RowGap)) < 0.5)
    host.app.animator.finishAll()
    Swag.require(list.openPath.isEmpty())
    Swag.require(Math.abs(below.position.y - (list.rows[1].position.bottom() + VaultList.RowGap)) < 0.5)
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
    Swag.require(window.operation.kind == .None)
    Swag.require(window.chosenLockedPath() == first.toString() and window.startupWaiting == first)
    Swag.require(window.readOnly.isChecked() and window.selectedMountPoint() == "D:")
    Swag.require(window.list.card.panel.isLocallyVisible())

    window.foldVault()
    Swag.require(window.chosenLockedPath() == second.toString() and window.startupWaiting == second)
    Swag.require(not window.readOnly.isChecked())

    window.chooseVault(first)
    Swag.require(window.chosenLockedPath() == first.toString() and window.startupQueue.isEmpty())
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
    Swag.require(window.startupVaults.count == 1)
    Swag.require(window.startupVaults[0].path == "C:\\one")
    Swag.require(window.startupVaults[0].drive == "mount-x")
    Swag.require(window.startupVaults[0].needsPassword)
    Swag.require(Utf8.endsWith(window.vaultIdentity("C:\\one"), appStrings().ui_StateAtStartup))

    discard window.mountedDrives.detach(0)
    Swag.require(window.startupVaults.count == 1)
    Swag.require(Utf8.endsWith(window.vaultIdentity("C:\\one"), appStrings().ui_StateAtStartup))

    window.mountedDrives.drives.add(MountedDrive{null, "C:\\one", "mount-x", "X:", true, false, true, 0, 0})
    discard window.runCommand(VaultCommands.AtStartup)
    Swag.require(window.startupVaults.isEmpty())

    // Forgetting a vault takes its mark with it.
    window.mountedDrives.drives.clear()
    window.startupVaults.add(StartupVault{"C:\\one", "mount-x", true, false})
    window.forgetVault("C:\\one")
    Swag.require(window.startupVaults.isEmpty() and window.vaults.isEmpty())
}

// A capacity is read back the way a reader wrote it, and refused when it says nothing.
#test
{
    var host: Testing.HeadlessHost
    discard testSetupMainWindow(&host)

    Swag.require(capacityText(256 * 1024 * 1024) == "256 MiB")
    Swag.require(capacityText(2 * 1024 * 1024 * 1024) == "2 GiB")

    // A size that is not a whole gibibyte stays in mebibytes rather than growing a decimal.
    Swag.require(capacityText(1536 * 1024 * 1024) == "1536 MiB")

    Swag.require(parseCapacity("256", 0).bytes == 256 * 1024 * 1024)
    Swag.require(parseCapacity("2", 1).bytes == 2 * 1024 * 1024 * 1024)
    Swag.require(not parseCapacity("", 0).error.isEmpty())
    Swag.require(not parseCapacity("0", 0).error.isEmpty())
    Swag.require(not parseCapacity("12x", 0).error.isEmpty())
    Swag.require(not parseCapacity("18446744073709551615", 1).error.isEmpty())
}

// The creation dialog preserves the exact filename; a vault has no required extension.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    let path = Testing.tempFilePath("vault-vault-", "")
    host.acceptModalFileDialog(path)
    window.chooseContainer(window.createPath, true)

    Swag.require(host.autoHandled)
    Swag.require(path == window.createPath.text())
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

    Swag.require(host.autoHandled)
    Swag.require(window.chosenPath == path and window.vaults.count == 1)
    Swag.require(window.list.card.panel.isLocallyVisible())
    Swag.require(Path.equals(window.fileDlgState.currentFolder, Path.directoryName(path) orelse ""))

    host.clickModalButtonWhenShown(Dialog.BtnCancel)
    window.openVaultFile()
    Swag.require(host.autoHandled)
    Swag.require(Path.equals(window.fileDlgState.currentFolder, Path.directoryName(path) orelse ""))
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
    Swag.require(host.autoHandled)
    Swag.require(field.paths.count == 1)
    Swag.require(field.paths[0] == existing)

    let generated = Testing.tempFilePath("vault-key-random-", ".key")
    defer discard catch File.delete(generated)
    host.acceptModalFileDialog(generated)
    field.generate.sigPressed.call(cast(*Button, field.generate))
    Swag.require(host.autoHandled)
    Swag.require(field.paths.count == 2)
    Swag.require((expect File.info(generated)).size == 64)

    field.files.setSelectedIndex(0, notify: false)
    field.remove.sigPressed.call(cast(*Button, field.remove))
    Swag.require(field.paths.count == 1)
    Swag.require(field.paths[0] == generated)
}

// A container dropped on the location field fills it, exactly as browsing to it would.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    window.showPage(.Create, animate: false)
    Swag.require(host.dropFilesOnWnd(window.createPath, ["c:/vaults/private"]) == DropEffect.Copy)
    Swag.require(window.createPath.text() == "c:/vaults/private")

    // Filling the field is what makes the action live, whether a dialog or a drop wrote it.
    Swag.require(window.createButton.isEnabled())
}

// A container dropped anywhere else on the window joins the list, unfolded and ready for its access.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    window.showPage(.Options, animate: false)
    Swag.require(host.dropFilesOnWnd(window, ["c:/vaults/private"]) == DropEffect.Copy)

    Swag.require(window.page == .List)
    Swag.require(window.chosenPath == "c:/vaults/private")
    Swag.require(window.mountPassword.hasFocus())
}

// A filename extension never decides whether a dropped file is a container.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    Swag.require(host.dropFilesOnWnd(window, ["c:/vaults/private.anything"]) == DropEffect.Copy)
    Swag.require(window.chosenPath == "c:/vaults/private.anything")

    // Two files name no single vault to open.
    window.foldVault()
    Swag.require(host.dropFilesOnWnd(window, ["c:/vaults/a", "c:/vaults/b"]) == DropEffect.None)
    Swag.require(window.chosenPath.isEmpty() and window.vaults.isEmpty())
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
    Swag.require(not containsStateBytes(state.toSlice(), "private hidden credentials"))
    window.startupVaults.clear()
    window.protectHiddenOnMount = false
    loadMainWindowState(window, state.toSlice())
    Swag.require(window.startupVaults.count == 1 and window.startupVaults[0].protectHidden)
    Swag.require(not window.protectHiddenOnMount)
}

// Common task vocabulary reaches the real command in either shipped language.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer discard catch g_App.setLanguage(ReferenceLanguage)
    for french in [false, true]
    {
        expect g_App.setLanguage(french ? "fr" : ReferenceLanguage)
        host.notify(.LanguageChanged)
        window.lens.open(french ? "nouveau conteneur" : "new container")
        Swag.require(window.lens.chosenEntry()!.id == VaultCommands.NewVault)
        window.lens.close()
        window.lens.open(french ? "ouvrir conteneur" : "open container")
        Swag.require(window.lens.chosenEntry()!.id == VaultCommands.OpenFile)
        window.lens.close()
    }
}

// A first mouse-only visit can start a new vault and return to the list without a hidden key.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    host.settleAnimations(window)
    host.click(window.list.newVault.surfaceRect().center())
    host.settleAnimations(window)
    Swag.require(window.page == .Create and window.createPage.path.isVisible())
    host.click(window.createPage.head.back.surfaceRect().center())
    host.settleAnimations(window)
    Swag.require(window.page == .List and window.list.openFile.isVisible())
    window.openVault("C:\\vaults\\example")
    host.settleAnimations(window)
    Swag.require(window.list.card.panel.isVisible() and window.list.card.mount.isVisible())
    window.lens.open()
    Swag.require(window.lens.chosenEntry()!.id == VaultCommands.NewVault)
}
