#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui

// The size of the charter's pictures, which the goldens are taken at to be judged whole against them.
const PictureWidth  = 1280'f32
const PictureHeight = 800'f32

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

    let image = host.renderSettled(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&image, Format.toString("%.%", name, dark ? "encre" : "papier"))
}

// What the list looks like, against `vault.list`: a title, one vault mounted on its own ground
// with its actions, two at rest, the two quiet words, and the hint line. One host per palette:
// a render target keeps what the last paint left.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, width: PictureWidth, height: PictureHeight)
    fillPictureList(window)
    assertSurfaceGolden(&host, window, true, "list")
}

// The pointer on a locked vault raises its row and names what choosing it does, against
// `vault.list.hover.paper`.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, width: PictureWidth, height: PictureHeight)
    fillPictureList(window)
    window.applyLayout()
    host.moveMouse(window.list.rows[1].surfaceRect().center())
    Swag.require(window.list.rows[1].hovered)
    assertSurfaceGolden(&host, window, false, "list.hover")
}

// The window without a vault, as privacy mode leaves it at every start, against `vault.home.paper`.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, width: PictureWidth, height: PictureHeight)
    assertSurfaceGolden(&host, window, false, "home")
}

// The Encre home while a file is dragged over it, with the Voltage target around the content.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, width: PictureWidth, height: PictureHeight)
    host.theme.setDark()
    host.notify(.ThemeChanged)
    window.applyLayout()

    var point = window.surfaceRect().center()
    window.surface!.surfaceToScreen(&point)
    Swag.require(host.dragFilesOver(point, ["/vaults/private"]) == DropEffect.Copy)
    Swag.require(window.dropHighlight.isLocallyVisible())
    Swag.require(not window.dropHighlight.prompt.isLocallyVisible())
    assertSurfaceGolden(&host, window, true, "drop")
    host.cancelDrag()
}

// A locked vault unfolded in place, against `vault.unlock.paper`.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, width: PictureWidth, height: PictureHeight)
    fillPictureList(window)
    window.chooseVault("/vault.bin")
    assertSurfaceGolden(&host, window, false, "unlock")
}

// The French explanation of a failed mount stays readable at minimum window width.
#[Swag.TestTag("golden")]
#test
{
    defer discard catch g_App.setLanguage(ReferenceLanguage)
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    fillPictureList(window)
    window.chooseVault("/vault.bin")

    host.clickModalButtonWhenShown(Dialog.BtnOk)
    window.finishMount(volumeError(.PasswordOrDamaged))

    // Finishing the mount refreshes the host's destinations. Use the same one on every platform.
    useTestDestination(window)
    window.list.arrange()
    assertSurfaceGolden(&host, window, true, "mount.failure")
}

// A failed mount uses the error as the title and puts the native code under the explanation.
#[Swag.TestTag("golden")]
#test
{
    defer discard catch g_App.setLanguage(ReferenceLanguage)
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, 1.25)
    defer host.shutdown()
    host.theme.setLight()
    host.notify(.ThemeChanged)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)

    var captured: bool
    host.app.sigFrame += func|host = &host, captured = &captured|(_)
    {
        if captured[] do
            return
        for surface in host.app.surfaces
        {
            if surface.view() is MessageDlg as dialog
            {
                let texts = appStrings()
                Swag.require(dialog.label.text() == texts.msg_ErrDriverUnavailable)
                let detail = unwrap dialog.detailLabel
                Swag.require(detail.text() == Format.toString(texts.msg_ErrorCode, 5))
                let image = host.renderSurface(surface)
                Pixel.Testing.assertImageGolden(&image, "mount.error.dialog.papier")
                captured[] = true
                dialog.closeWithResult(Dialog.BtnOk)
                return
            }
        }
    }

    window.finishMount(volumeError(.DriverUnavailable, 5))
    Swag.require(captured)
}

// A French modification menu keeps its opener and the access fields visible at minimum size.
#[Swag.TestTag("golden")]
#test
{
    defer discard catch g_App.setLanguage(ReferenceLanguage)
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    host.theme.setDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    fillPictureList(window)
    window.chooseVault("/vault.bin")
    host.settleAnimations(window)

    var captured: bool
    host.app.sigFrame += func|host = &host, captured = &captured|(_)
    {
        if captured[] do
            return
        let menu = unwrap host.capturedPopupMenu()
        Swag.require(menu.items.count == 3)
        let image = host.render(&host.surfaceWnd)
        Pixel.Testing.assertImageGolden(&image, "unlock.modify.encre")
        captured[] = true
        Swag.require(host.dismissPopupMenu())
    }

    host.clickWnd(unwrap window.list.card.header.modify)
    Swag.require(captured)
}

// Right-clicking a locked vault shows the mounting, editing, and list actions in groups.
#[Swag.TestTag("golden")]
#test
{
    defer discard catch g_App.setLanguage(ReferenceLanguage)
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, width: PictureWidth, height: PictureHeight)
    defer host.shutdown()

    host.theme.setLight()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    fillPictureList(window)
    host.settleAnimations(window)

    var captured: bool
    host.app.sigFrame += func|host = &host, captured = &captured|(_)
    {
        if captured[] do
            return
        let menu = unwrap host.capturedPopupMenu()
        Swag.require(menu.items.count == 11)
        Swag.require(menu.items[1]!.separator and menu.items[4]!.separator and menu.items[8]!.separator)
        let image = host.render(&host.surfaceWnd)
        Pixel.Testing.assertImageGolden(&image, "list.context.papier")
        captured[] = true
        Swag.require(host.dismissPopupMenu())
    }

    host.clickWnd(unwrap window.list.rowOf("/vault.bin"), .Right)
    Swag.require(captured)
}

// The page that creates a vault, against `vault.create.paper`.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, width: PictureWidth, height: PictureHeight)
    window.showPage(.Create, animate: false)
    window.createPath.setText("/home/vault/Documents/papiers.bin")

    // The room left on a volume belongs to the machine, so the picture states it.
    window.createPage.showFreeSpace(212'u64 * 1024 * 1024 * 1024, "/")
    assertSurfaceGolden(&host, window, true, "create")
}

// The randomisation of a new container, against `vault.progress`.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, width: PictureWidth, height: PictureHeight)
    window.progressPage.begin("/home/vault/papiers.bin", .Randomizing)
    window.progressPage.setProgress(0.62, 159 * 1024 * 1024, 256 * 1024 * 1024, 12)
    window.showPage(.Progress, animate: false)
    assertSurfaceGolden(&host, window, false, "progress")
}

// The privacy page, against `vault.options`.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, width: PictureWidth, height: PictureHeight)
    window.optionsPage.driverAction?.hide()
    window.showPage(.Options, animate: false)
    assertSurfaceGolden(&host, window, true, "options")
}

// File actions stay first above the chosen vault, including French at a non-default scale.
#[Swag.TestTag("golden")]
#test
{
    defer discard catch g_App.setLanguage(ReferenceLanguage)
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, 1.25)
    host.theme.setLight()
    host.notify(.ThemeChanged)

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    useTestDestination(window)
    window.openVault("/vaults/example")
    window.lens.open()
    Swag.require(window.lens.chosenEntry()!.id == VaultCommands.NewVault)
    let image = host.renderSettled(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&image, "surface.lens.paper")
}

// The timeout menu floats above the actual privacy form, with its neighbouring controls visible.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, width: PictureWidth, height: PictureHeight)
    window.optionsPage.driverAction?.hide()
    window.showPage(.Options, animate: false)
    window.unmountOnIdle.toggle()
    window.applyLayout()
    host.finishAnimations()
    var captured: bool
    host.app.sigFrame += func|host = &host, captured = &captured|(_)
    {
        if captured[] do
            return
        Swag.require(host.capturedPopupMenu() != null)
        var image = host.render(&host.surfaceWnd)
        Pixel.Testing.assertImageGolden(&image, "options.timeout.menu")
        captured[] = true
        Swag.require(host.dismissPopupMenu())
    }

    window.idleTimeout.sigLinkActivated.call(window.idleTimeout, "")
    Swag.require(captured)
}

// The key-file editor shows the configured paths and names each action beside the list.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, width: PictureWidth, height: PictureHeight)

    var options: FormDlgOptions
    options.title = appStrings().dlg_TitleChangeKeyFiles
    options.confirmButtonText = appStrings().dlg_BtnApply
    let dialog = FormDlg.create(unwrap window.surface, options)
    var paths: Array'String
    for index in 10 do
        paths.add(Format.toString("/home/alice/keys/key-%.key", index + 1))
    let field = buildKeyFileChangeForm(dialog, paths.toSlice())
    dialog.fitHeightToContent(dialog.form.measure(Math.Point{dialog.form.position.width, 0}).preferred.y)
    dialog.applyLayout()
    Swag.require(field.files.lineCount() == 10)

    let image = host.renderSurface(unwrap dialog.surface)
    Pixel.Testing.assertImageGolden(&image, "keyfiles.encre")
}

// A resize with custom capacity shows the capacity option, value and unit in reading order.
#[Swag.TestTag("golden")]
#test
{
    defer discard catch g_App.setLanguage(ReferenceLanguage)
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, 1.25)
    defer host.shutdown()
    host.theme.setLight()
    host.notify(.ThemeChanged)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)

    let texts  = appStrings()
    let dialog = FormDlg.create(unwrap window.surface, {title: texts.dlg_TitleResize, confirmButtonText: texts.dlg_BtnApply})
    let fields = buildVaultResizeForm(dialog)
    fields.keepCapacity.toggle()
    fields.capacity.setText("512")
    dialog.fitHeightToContent(dialog.form.measure({dialog.form.position.width, 0}).preferred.y)
    dialog.applyLayout()
    let image = host.renderSurface(unwrap dialog.surface)
    Pixel.Testing.assertImageGolden(&image, "resize.papier")
}

// The longest vault form keeps its warning, access fields, and actions visible together.
#[Swag.TestTag("golden")]
#test
{
    defer discard catch g_App.setLanguage(ReferenceLanguage)
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, 1.25)
    defer host.shutdown()
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)

    let texts  = appStrings()
    let dialog = FormDlg.create(unwrap window.surface, {title: texts.dlg_TitleCreateHidden, confirmButtonText: texts.dlg_BtnCreate})
    let fields = buildHiddenCreateForm(dialog)
    dialog.fitHeightToContent(dialog.form.measure({dialog.form.position.width, 0}).preferred.y)
    dialog.applyLayout()
    Swag.require(fields.keyFiles.empty.isLocallyVisible())
    Swag.require(fields.keyFiles.remove.position.right() <= fields.keyFiles.actions.clientRect().right() + 0.5)
    let image = host.renderSurface(unwrap dialog.surface)
    Pixel.Testing.assertImageGolden(&image, "hidden.create.encre")
}

// Mount keeps the chosen key files visible in the unfolded card instead of opening another form.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, width: PictureWidth, height: PictureHeight)
    fillPictureList(window)
    window.chooseVault("/vault.bin")
    let titleX = window.list.title.position.x
    for index in 3 do
        window.unlockKeyFiles.add(Format.toString("/home/alice/keys/mount-%.key", index + 1))
    window.list.refresh()
    window.list.card.toggleKeyFiles()
    assertSurfaceGolden(&host, window, true, "unlock.keys")
    Swag.require(window.list.title.position.x == titleX)
}
