using Core, Gui, Pixel

const AppIcon = #include("../datas/appicon.png")

var g_App: Application
var g_Surface: #null *Surface
var g_CreatePath: #null *EditBox
var g_CreateSize: #null *EditBox
var g_CreateUnit: #null *ComboBox
var g_MountPath: #null *EditBox
var g_Drive: #null *ComboBox
var g_MountButton: #null *PushButton
var g_DismountButton: #null *PushButton
var g_Status: #null *Label
var g_CreatePassword: #null *PasswordEdit
var g_ConfirmPassword: #null *PasswordEdit
var g_MountPassword: #null *PasswordEdit
var g_Mounted: #null *SCrypt.Platform.MountedVolume
var g_FileDlgState: FileDlgState

func surface()->*Surface => notnull g_Surface

func caughtMessage(err: #null any)->string
{
    switch err
    {
    case SCrypt.Error:
        return (cast(SCrypt.Error) err).message orelse "sCrypt error."
    case Swag.SystemError:
        return (cast(Swag.SystemError) err).message orelse "System error."
    }
    return "The operation failed."
}

func showError(message: string, err: #null any = null)
{
    let detail = err == null ? message : Format.toString("%\n\n%", message, caughtMessage(err))
    MessageDlg.error(surface(), detail)
}

func updateMountState()
{
    let mounted = g_Mounted != null
    g_MountButton?.enable(!mounted)
    g_DismountButton?.enable(mounted)
    g_Drive?.enable(!mounted)
    g_MountPath?.enable(!mounted)
}

func chooseContainer(target: *EditBox, create: bool)
{
    var options: FileDlgOptions
    options.state             = &g_FileDlgState
    options.mode              = create ? .CreateFile : .SelectFile
    options.title             = create ? "Create an sCrypt container" : "Open an encrypted container"
    options.confirmButtonText = create ? "Create" : "Open"
    options.initialName       = create ? "volume.scrypt" : ""
    options.filters.add({"sCrypt encrypted container (*.scrypt)", ".scrypt"})
    options.shortcuts.add({Env.SpecialDirectory.Desktop, "Desktop"})
    options.shortcuts.add({Env.SpecialDirectory.UserDocuments, "Documents"})

    // Keep the stronger modal depth local to sCrypt. The shared dark and light
    // themes retain their original surface geometry and dialog presentation.
    let oldShadowSize   = g_App.theme.metrics.surfaceWnd_ShadowSize
    let oldCornerRadius = g_App.theme.metrics.surfaceWnd_CornerRadius
    g_App.theme.metrics.surfaceWnd_ShadowSize   = 10
    g_App.theme.metrics.surfaceWnd_CornerRadius = 1
    defer
    {
        g_App.theme.metrics.surfaceWnd_ShadowSize   = oldShadowSize
        g_App.theme.metrics.surfaceWnd_CornerRadius = oldCornerRadius
    }

    let dialog = FileDlg.create(surface(), options)
    (notnull dialog.surface).updateFlags(add: .Border)
    for button in dialog.buttons where button.id == Dialog.BtnCancel do
        button.setForm(.Normal)
    if dialog.doModal() == Dialog.BtnOk do
        target.setText(dialog.selectedPath())
}

func containerSize()->u64 fail
{
    let text = (notnull g_CreateSize).text()
    let parsed = catch StrConv.parseU64(text) as parseError
    if parseError != null or parsed.ovf or parsed.eat != @countof(text) or !parsed.value do
        SCrypt.failWith("The container size is invalid.")
    let unit = (notnull g_CreateUnit).selectedIndex
    let multiplier = unit == 0 ? 1024'u64 * 1024 : 1024'u64 * 1024 * 1024
    if parsed.value > Swag.U64.Max / multiplier do
        SCrypt.failWith("The container size is too large.")
    let result = parsed.value * multiplier
    if result < SCrypt.MinimumSize do
        SCrypt.failWith(Format.toString("The minimum container size is % MiB.",
                                        (SCrypt.MinimumSize + 1024 * 1024 - 1) / (1024 * 1024)))
    return result
}

func createContainer()
{
    let path = (notnull g_CreatePath).text()
    if !@countof(path)
    {
        showError("Choose the container file to create.")
        return
    }
    if File.exists(path)
    {
        showError("This file already exists. Choose a new name to avoid data loss.")
        return
    }
    if (notnull g_CreatePassword).isEmpty()
    {
        showError("A password is required.")
        return
    }
    if !Core.Crypto.constantTimeEqual((notnull g_CreatePassword).bytes(), (notnull g_ConfirmPassword).bytes())
    {
        showError("The passwords do not match.")
        return
    }

    let size = catch containerSize() as sizeError
    if sizeError != null
    {
        showError("Could not create the container.", sizeError)
        return
    }

    (notnull g_Status).setText("Creating and randomizing the container…")
    Cursor.activateWait()
    var volume = catch SCrypt.Volume.create(path, (notnull g_CreatePassword).bytes(), size) as createError
    (notnull g_CreatePassword).clear()
    (notnull g_ConfirmPassword).clear()
    if createError != null
    {
        showError("Could not create the container.", createError)
        (notnull g_Status).setText("Container creation failed.")
        return
    }
    volume.close()
    (notnull g_Status).setText("Container created. It is ready to mount.")
    (notnull g_MountPath).setText(path)
}

func selectedMountPoint()->String
{
    let combo = notnull g_Drive
    let item = combo.selectedItem()
    if !item do
        return ""
    return (notnull item).name.raw
}

func mountContainer()
{
    let path = (notnull g_MountPath).text()
    if !@countof(path)
    {
        showError("Choose an existing container.")
        return
    }
    if (notnull g_MountPassword).isEmpty()
    {
        showError("A password is required.")
        return
    }
    let mountPoint = selectedMountPoint()
    if mountPoint.isEmpty()
    {
        showError("No drive letter is available.")
        return
    }

    (notnull g_Status).setText("Starting the portable filesystem driver…")
    Cursor.activateWait()
    let mounted = Memory.new'SCrypt.Platform.MountedVolume()
    discard catch SCrypt.Platform.MountedVolume.open(
        mounted, path, (notnull g_MountPassword).bytes(), mountPoint) as mountError
    (notnull g_MountPassword).clear()
    if mountError != null
    {
        Memory.delete(mounted)
        showError("Could not mount the virtual disk.", mountError)
        (notnull g_Status).setText("Mount failed.")
        return
    }

    g_Mounted = mounted
    (notnull g_Status).setText(Format.toString(
        "Encrypted drive mounted on %. It will unmount when sCrypt closes.", mountPoint))
    updateMountState()
}

func dismountContainer(showFailure = true)
{
    if !g_Mounted do
        return
    Cursor.activateWait()
    let mounted = notnull g_Mounted
    discard catch mounted.close() as closeError
    Memory.delete(mounted)
    g_Mounted = null
    updateMountState()
    if closeError != null and showFailure do
        showError("The drive was unmounted, but the final synchronization failed.", closeError)
    elif g_Status do
        (notnull g_Status).setText("Drive unmounted safely.")
}

func shutdown()
{
    dismountContainer(false)
    g_CreatePassword?.clear()
    g_ConfirmPassword?.clear()
    g_MountPassword?.clear()
}

func rootEvent(wnd: *Wnd, evt: IEvent)->bool
{
    discard wnd
    if evt is DestroyEvent do
        shutdown()
    return false
}

func addFieldLabel(parent: *Wnd, text: string, x, y, width = 420'f32)
{
    let label = Label.create(parent, text, {x, y, width, 24}, null, .SecondaryText)
    label.setTextAlignment(.Left, .Center)
    label.style.setFont(parent.theme().createDefaultFont(13, .Bold), .Regular)
}

func createCard(parent: *Wnd, title, subtitle: string, position: Math.Rectangle)->*Wnd
{
    let frame = Wnd.create'FrameWnd(parent, position)
    frame.setFrameForm(.Square)
    frame.setFrameFlags(.Borders)

    let view = frame.createView'Wnd()
    with let brandRail = Wnd.create'Wnd(view, {0, 0, 4, position.height})
    {
        .backgroundStyle = .Window
        .style.addStyleSheetColors("wnd_Bk $hilight")
    }

    let titleLabel = Label.create(view, title, {22, 16, position.width - 44, 30})
    titleLabel.setTextAlignment(.Left, .Center)
    titleLabel.style.setFont(view.theme().createDefaultFont(21, .Bold), .Regular)

    let subtitleLabel = Label.create(view, subtitle, {22, 48, position.width - 44, 42}, null,
                                      .WordWrap | .SecondaryText)
    subtitleLabel.setTextAlignment(.Left, .Top)
    return view
}

func populateDrives(combo: *ComboBox)
{
    let available = File.availableDriveLetters()
    for letter in available where letter >= 'D' do
        combo.addItem(Format.toString("%:", letter))
    for letter in available where letter < 'D' do
        combo.addItem(Format.toString("%:", letter))
    if combo.items.count do
        combo.setSelectedIndex(0, false)
}

#main
{
    if SCrypt.Platform.isPortableGuardianInvocation() do
        Env.exit(SCrypt.Platform.runPortableGuardian())

    #static if #hastag("SCrypt.Integration")
    {
        if SCrypt.Integration.isVisibilityProbeInvocation() do
            Env.exit(SCrypt.Integration.runVisibilityProbe())
        SCrypt.Integration.runAndExit()
    }

    let appIcon = expect Image.decode(".png", AppIcon)
    g_App.setAppIcon(appIcon)
    g_Surface = try g_App.createSurface(80, 50, 1100, 790, SurfaceFlags.StandardWindow)
    g_App.theme.setSwagDark()
    g_App.notifyThemeChanged()
    let mainSurface = surface()
    mainSurface.minSize = {1100, 790}
    mainSurface.setTitle("sCrypt — Private virtual drives")
    let root = mainSurface.view()
    root.hookOnEvent = &rootEvent
    root.backgroundStyle = .View

    with let brandRail = Wnd.create'Wnd(root, {30, 24, 4, 70})
    {
        .backgroundStyle = .Window
        .style.addStyleSheetColors("wnd_Bk $hilight")
    }

    let title = Label.create(root, "sCrypt", {46, 22, 420, 46})
    title.setTextAlignment(.Left, .Center)
    title.style.setFont(root.theme().createDefaultFont(36, .Bold), .Regular)

    let subtitle = Label.create(root,
        "Encrypted storage that looks and behaves like a regular Windows drive.",
        {48, 70, 760, 28}, null, .SecondaryText)
    subtitle.setTextAlignment(.Left, .Center)
    let badge = Label.create(root, "PORTABLE  •  PASSWORD-LOCKED  •  NO SETUP",
                             {742, 34, 320, 28}, null, .SecondaryText)
    badge.setTextAlignment(.Right, .Center)
    badge.style.setFont(root.theme().createDefaultFontFS(12, .Bold), .Regular)

    let createView = createCard(root, "Create a new vault",
        "Choose a fixed capacity. The complete container is randomized before it is ready.",
        {30, 122, 505, 500})

    addFieldLabel(createView, "CONTAINER FILE", 22, 104)
    g_CreatePath = EditBox.create(createView, "", {22, 130, 344, 34})
    (notnull g_CreatePath).setPlaceholder("C:\\path\\private.scrypt")
    (notnull g_CreatePath).setIcon(root.theme().icon24(ThemeIcons24.OpenFile, 17))
    let browseCreate = PushButton.create(createView, "Browse", {376, 130, 102, 34})
    browseCreate.setIcon(root.theme().icon24(ThemeIcons24.OpenFile, 16))
    browseCreate.sigPressed += func(btn) { discard btn; chooseContainer(notnull g_CreatePath, true); }

    addFieldLabel(createView, "FIXED CAPACITY", 22, 182)
    g_CreateSize = EditBox.create(createView, "256", {22, 208, 168, 34})
    (notnull g_CreateSize).setUnsignedIntegerRange(1, 1024 * 1024)
    g_CreateUnit = ComboBox.create(createView, {200, 208, 108, 34})
    (notnull g_CreateUnit).addItem("MiB")
    (notnull g_CreateUnit).addItem("GiB")
    (notnull g_CreateUnit).setSelectedIndex(0, false)

    addFieldLabel(createView, "PASSWORD", 22, 260)
    g_CreatePassword = PasswordEdit.create(createView, {22, 286, 456, 34})
    (notnull g_CreatePassword).setPlaceholder("Required password")
    addFieldLabel(createView, "CONFIRM PASSWORD", 22, 338)
    g_ConfirmPassword = PasswordEdit.create(createView, {22, 364, 456, 34})
    (notnull g_ConfirmPassword).setPlaceholder("Enter the password again")
    let createButton = PushButton.create(createView, "Create encrypted vault",
                                          {250, 430, 228, 38}, form: .Strong)
    createButton.setIcon(root.theme().icon24(ThemeIcons24.SaveAs, 18))
    createButton.sigPressed += func(btn) { discard btn; createContainer(); }

    let mountView = createCard(root, "Mount an existing vault",
        "Unlock a container and expose it on any currently available drive letter.",
        {565, 122, 505, 500})

    addFieldLabel(mountView, "CONTAINER FILE", 22, 104)
    g_MountPath = EditBox.create(mountView, "", {22, 130, 344, 34})
    (notnull g_MountPath).setPlaceholder("Existing encrypted container")
    (notnull g_MountPath).setIcon(root.theme().icon24(ThemeIcons24.OpenFile, 17))
    let browseMount = PushButton.create(mountView, "Browse", {376, 130, 102, 34})
    browseMount.setIcon(root.theme().icon24(ThemeIcons24.OpenFile, 16))
    browseMount.sigPressed += func(btn) { discard btn; chooseContainer(notnull g_MountPath, false); }

    addFieldLabel(mountView, "PASSWORD", 22, 182)
    g_MountPassword = PasswordEdit.create(mountView, {22, 208, 456, 34})
    (notnull g_MountPassword).setPlaceholder("Container password")
    addFieldLabel(mountView, "DRIVE LETTER", 22, 260)
    g_Drive = ComboBox.create(mountView, {22, 286, 128, 34})
    populateDrives(notnull g_Drive)

    let mountNote = Label.create(mountView,
        "The drive is fully available to Windows while sCrypt is running, and disappears when the app closes.",
        {22, 338, 456, 54}, null, .WordWrap | .SecondaryText)
    mountNote.setTextAlignment(.Left, .Top)

    g_MountButton = PushButton.create(mountView, "Mount drive", {188, 430, 140, 38}, form: .Strong)
    (notnull g_MountButton).setIcon(root.theme().icon24(ThemeIcons24.Play, 18))
    (notnull g_MountButton).sigPressed += func(btn) { discard btn; mountContainer(); }
    g_DismountButton = PushButton.create(mountView, "Unmount", {338, 430, 140, 38})
    (notnull g_DismountButton).setIcon(root.theme().icon24(ThemeIcons24.Stop, 18))
    (notnull g_DismountButton).sigPressed += func(btn) { discard btn; dismountContainer(); }

    let statusFrame = Wnd.create'FrameWnd(root, {30, 642, 1040, 64})
    statusFrame.setFrameForm(.Square)
    statusFrame.setFrameFlags(.Borders)
    let statusView = statusFrame.createView'Wnd()
    let statusIcon = Label.create(statusView, "", {14, 8, 30, 40})
    var statusGlyph = root.theme().icon24(ThemeIcons24.About, 22)
    statusGlyph.color = root.themeColors().label_TextLight
    statusIcon.setIcon(statusGlyph)
    g_Status = Label.create(statusView, "Ready — create a vault or choose one to mount.",
                             {52, 8, 956, 40})
    (notnull g_Status).setTextAlignment(.Left, .Center)
    Label.create(root,
        "WinFsp - Windows File System Proxy, Copyright (C) Bill Zissimopoulos — github.com/winfsp/winfsp",
        {34, 720, 1032, 22}, null, .SecondaryText).setTextAlignment(.Left, .Center)
    updateMountState()

    mainSurface.show()
    g_App.run()
    shutdown()
}
