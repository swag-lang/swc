using Core, Gui, Pixel

private struct VaultCard
{
    frame: *FrameWnd = undefined
    body:  *Wnd      = undefined
}

private func createVaultCard(parent: *Wnd, title, subtitle: string)->VaultCard
{
    let frame = Wnd.create'FrameWnd(parent)
    frame.setFrameForm(.Square)
    frame.setFrameFlags(.Borders)

    let view = frame.createView'Wnd()
    view.padding = {18, 16, 18, 16}

    with let brandRail = Wnd.create'Wnd(view, {0, 0, 4})
    {
        .dockStyle       = .Left
        .margin.z        = 18
        .backgroundStyle = .Window
        .style.addStyleSheetColors("wnd_Bk $hilight")
    }

    let titleLabel = Label.create(view, title, {0, 0, 0, 34})
    titleLabel.dockStyle = .Top
    titleLabel.setTextAlignment(.Left, .Center)
    titleLabel.style.setFont(view.theme().createDefaultFont(21, .Bold), .Regular)

    let subtitleLabel = Label.create(view, subtitle, {0, 0, 0, 54}, null, .WordWrap | .SecondaryText)
    subtitleLabel.dockStyle = .Top
    subtitleLabel.setTextAlignment(.Left, .Top)

    let body = Wnd.create'Wnd(view)
    body.dockStyle       = .Center
    body.backgroundStyle = .Transparent
    view.applyLayout()
    return {frame, body}
}

private func createVaultFields()->Array'FormFieldDefinition
{
    var result: retval
    result.add({id: "create.path", label: "CONTAINER FILE", placeholder: "C:\\path\\private.scrypt", actionText: "Browse"})

    var capacity: FormFieldDefinition
    capacity.id          = "create.size"
    capacity.label       = "FIXED CAPACITY"
    capacity.initialText = "256"
    capacity.choices.add({"MiB", "mib"})
    capacity.choices.add({"GiB", "gib"})
    result.add(#move capacity)

    result.add({id: "create.password", label: "PASSWORD", kind: FormFieldKind.Password, placeholder: "Required password"})
    result.add({id: "create.confirm", label: "CONFIRM PASSWORD", kind: FormFieldKind.Password, placeholder: "Enter the password again"})
    return result
}

private func mountVaultFields()->Array'FormFieldDefinition
{
    var result: retval
    result.add({id: "mount.path", label: "CONTAINER FILE", placeholder: "Existing encrypted container", actionText: "Browse"})
    result.add({id: "mount.password", label: "PASSWORD", kind: FormFieldKind.Password, placeholder: "Container password"})

    var drive: FormFieldDefinition
    drive.id    = "mount.drive"
    drive.label = "DRIVE LETTER"
    drive.kind  = .Choice
    let available = File.availableDriveLetters()
    for letter in available where letter >= 'D'
    {
        var choice: FormChoice
        choice.text = Format.toString("%:", letter)
        drive.choices.add(#move choice)
    }

    for letter in available where letter < 'D'
    {
        var choice: FormChoice
        choice.text = Format.toString("%:", letter)
        drive.choices.add(#move choice)
    }

    result.add(#move drive)
    return result
}

private func createHeader(parent: *Wnd)
{
    let header = Wnd.create'Wnd(parent, {0, 0, 0, 104})
    header.dockStyle = .Top
    header.margin    = {30, 18, 30, 0}

    with let brandRail = Wnd.create'Wnd(header, {0, 0, 4})
    {
        .dockStyle       = .Left
        .margin.z        = 12
        .backgroundStyle = .Window
        .style.addStyleSheetColors("wnd_Bk $hilight")
    }

    let badge = Label.create(header, "PORTABLE  |  PASSWORD-LOCKED  |  NO SETUP", {0, 0, 330}, null, .SecondaryText)
    badge.dockStyle = .Right
    badge.setTextAlignment(.Right, .Center)
    badge.style.setFont(parent.theme().createDefaultFontFS(12, .Bold), .Regular)

    let title = Label.create(header, "sCrypt", {0, 0, 0, 48})
    title.dockStyle = .Top
    title.setTextAlignment(.Left, .Center)
    title.style.setFont(parent.theme().createDefaultFont(36, .Bold), .Regular)

    let subtitle = Label.create(header, "Encrypted storage that looks and behaves like a regular Windows drive.")
    subtitle.dockStyle = .Center
    subtitle.setTextAlignment(.Left, .Top)
    subtitle.updateFlags(add: .SecondaryText)
    header.applyLayout()
}

private func createFooter(window: *MainWindow)
{
    let footer = Label.create(window, "WinFsp - Windows File System Proxy, Copyright (C) Bill Zissimopoulos - github.com/winfsp/winfsp", {0, 0, 0, 24}, null, .SecondaryText)
    footer.dockStyle = .Bottom
    footer.margin    = {34, 4, 34, 12}
    footer.setTextAlignment(.Left, .Center)

    let statusFrame = Wnd.create'FrameWnd(window, {0, 0, 0, 64})
    statusFrame.dockStyle = .Bottom
    statusFrame.margin    = {30, 0, 30, 10}
    statusFrame.setFrameForm(.Square)
    statusFrame.setFrameFlags(.Borders)

    let statusView = statusFrame.createView'Wnd()
    statusView.padding = {14, 8, 14, 8}
    let statusIcon = Label.create(statusView, "", {0, 0, 30})
    statusIcon.dockStyle = .Left
    statusIcon.margin.z  = 8
    var statusGlyph = window.theme().icon24(ThemeIcons24.About, 22)
    statusGlyph.color = window.themeColors().label_TextLight
    statusIcon.setIcon(statusGlyph)

    window.status           = Label.create(statusView, "Ready - create a vault or choose one to mount.")
    window.status.dockStyle = .Center
    window.status.setTextAlignment(.Left, .Center)
    statusView.applyLayout()
}

private func createCreateCard(window: *MainWindow, parent: *GridLayoutCtrl)->*FrameWnd
{
    let card = createVaultCard(parent, "Create a new vault", "Choose a fixed capacity. The complete container is randomized before it is ready.")

    var options: FormLayoutOptions
    options.labelPlacement = .Above
    options.rowSpacing     = 10
    let definitions = createVaultFields()
    let form        = FormCtrl.create(card.body, definitions.toSlice(), options, {0, 0, 0, 304})
    form.dockStyle = .Top

    window.createPath      = notnull form.textField("create.path")
    window.createSize      = notnull form.textField("create.size")
    window.createUnit      = notnull (notnull form.findField("create.size")).accessoryChoice
    window.createPassword  = notnull form.passwordField("create.password")
    window.confirmPassword = notnull form.passwordField("create.confirm")
    window.createPath.setIcon(window.theme().icon24(ThemeIcons24.OpenFile, 17))
    let browse = notnull (notnull form.findField("create.path")).action
    browse.setIcon(window.theme().icon24(ThemeIcons24.OpenFile, 16))
    form.sigAction += func|window|(form, id)
    {
        discard form
        if id == "create.path" do
            window.chooseContainer(window.createPath, true)
    }
    window.createSize.setUnsignedIntegerRange(1, 1024 * 1024)

    let actions = StackLayoutCtrl.create(card.body, .Right, {0, 0, 0, 38})
    actions.dockStyle   = .Bottom
    window.createButton = PushButton.create(actions, "Create encrypted vault", {0, 0, 228, 38}, form: .Strong)
    window.createButton.setIcon(window.theme().icon24(ThemeIcons24.SaveAs, 18))
    window.createButton.sigPressed += func|window|(btn)
    {
        discard btn
        window.createContainer()
    }
    actions.computeLayout()
    card.body.applyLayout()
    return card.frame
}

private func createMountCard(window: *MainWindow, parent: *GridLayoutCtrl)->*FrameWnd
{
    let card = createVaultCard(parent, "Mount an existing vault", "Unlock a container and expose it on any currently available drive letter.")

    var options: FormLayoutOptions
    options.labelPlacement = .Above
    options.rowSpacing     = 10
    let definitions = mountVaultFields()
    let form        = FormCtrl.create(card.body, definitions.toSlice(), options, {0, 0, 0, 224})
    form.dockStyle = .Top

    window.mountPath     = notnull form.textField("mount.path")
    window.mountPassword = notnull form.passwordField("mount.password")
    window.drive         = notnull form.choiceField("mount.drive")
    window.mountPath.setIcon(window.theme().icon24(ThemeIcons24.OpenFile, 17))
    let browse = notnull (notnull form.findField("mount.path")).action
    browse.setIcon(window.theme().icon24(ThemeIcons24.OpenFile, 16))
    form.sigAction += func|window|(form, id)
    {
        discard form
        if id == "mount.path" do
            window.chooseContainer(window.mountPath, false)
    }

    let note = Label.create(card.body, "The drive is available to Windows while sCrypt runs, then disappears when the app closes.", {0, 0, 0, 54}, null, .WordWrap | .SecondaryText)
    note.dockStyle = .Top
    note.setTextAlignment(.Left, .Top)

    let actions = StackLayoutCtrl.create(card.body, .Right, {0, 0, 0, 38})
    actions.dockStyle    = .Bottom
    window.unmountButton = PushButton.create(actions, "Unmount", {0, 0, 140, 38})
    window.unmountButton.setIcon(window.theme().icon24(ThemeIcons24.Stop, 18))
    window.unmountButton.sigPressed += func|window|(btn)
    {
        discard btn
        window.unmountContainer()
    }
    window.mountButton = PushButton.create(actions, "Mount drive", {0, 0, 140, 38}, form: .Strong)
    window.mountButton.setIcon(window.theme().icon24(ThemeIcons24.Play, 18))
    window.mountButton.sigPressed += func|window|(btn)
    {
        discard btn
        window.mountContainer()
    }
    actions.computeLayout()
    card.body.applyLayout()
    return card.frame
}

impl MainWindow
{
    func create(parent: *Wnd)->*MainWindow
    {
        let result  = Wnd.create'MainWindow(parent, "sCrypt.mainWindow")
        let surface = notnull result.surface
        surface.setView(result)
        surface.minSize        = {1100, 790}
        result.backgroundStyle = .View

        createHeader(result)
        createFooter(result)

        let cards = GridLayoutCtrl.create(result, 2, 1)
        cards.dockStyle         = .Center
        cards.margin            = {30, 0, 30, 14}
        cards.horizontalSpacing = 30
        cards.setColumnTrack(0, .Fraction, 1)
        cards.setColumnTrack(1, .Fraction, 1)
        cards.setRowTrack(0, .Fraction, 1)
        cards.setCell(createCreateCard(result, cards), 0, 0)
        cards.setCell(createMountCard(result, cards), 1, 0)

        result.applyLayout()
        cards.computeLayout()
        result.setState(.Ready)
        return result
    }

    // Releases any pending operation and mounted volume before application exit.
    mtd shutdown()
    {
        .shutdownInternal()
    }
}
