using Core, Gui, Pixel

// The vault the reader chose, unfolded in place: the access that opens it and the drive it opens on.
//
// It is a floating panel laid over the row it unfolds, so the vault keeps its place in the list
// while the other rows recede behind it. Its head is the row itself, drawn again; under it, the
// password, then one line of quiet choices — the drive, the key files, read only — and the one
// primary action, Mount. The access stated here is also what every change of the vault reads:
// its password, its key files, its capacity, its hidden volume.
struct UnlockCard
{
    late
    {
        panel:      *FloatingPanel
        header:     *VaultRow
        form:       *FormLayoutCtrl
        password:   *PasswordEdit
        options:    *StackLayoutCtrl
        driveLabel: *Label
        drive:      *ComboBox
        keyFiles:   *IconButton
        readOnly:   *CheckButton
        mount:      *PushButton
    }
}

impl UnlockCard
{
    // Air between the password and the line of choices, and under that line.
    const OptionsGap    = 16'f32
    const BottomPadding = 24'f32

    // Creates the card, hidden, over the rows of `list`.
    func create(list: *Wnd, window: *MainWindow)->UnlockCard
    {
        var result: #returntype

        with result.panel = FloatingPanel.create(list, {}, "vault.unlock")
        {
            .padding = 0
            .hide()
        }

        result.header = VaultRow.create(result.panel, window, header: true)

        var formOptions: FormLayoutOptions
        formOptions.labelFlags       = .SecondaryText
        result.form                  = FormLayoutCtrl.create(result.panel, formOptions)
        result.password              = result.form.addPasswordField(appStrings().ui_Password, placeholder: appStrings().ui_ContainerPassword)
        result.password.sigChanged   += func|window|(_) { window.refreshActions() }
        result.password.sigSubmitted += func|window|(_) { window.submitMount() }

        // The quiet choices of the mount, in the order a reader settles them.
        let metrics = list.themeMetrics()
        with result.options = StackLayoutCtrl.create(result.panel, .Left)
        {
            .backgroundStyle = .Transparent
            .spacing         = metrics.dialog_BtnPadding
        }

        with result.driveLabel = Label.create(result.options, appStrings().ui_Drive, {}, null, .SecondaryText)
        {
            .setTextAlignment(.Left, .OpticalCenter)
        }

        // The picker is as wide as the letter it shows, not as a field of a form.
        with result.drive = ComboBox.create(result.options, Math.Rectangle{0, 0, 0, metrics.comboBox_Height}, flags: .Flat)
        {
            .layoutSpec.alignY = .Center
            .style.setStyleSheetMetrics("comboBox_Width 0")
            .margin.z = metrics.dialog_BtnPadding * 2
            setMachineFont(result.drive)
            .sigChanged += func|window|(_, _) { window.refreshActions() }
        }

        with result.keyFiles = createQuietLink(result.options, appStrings().ui_KeyFilesLink)
        {
            .layoutSpec.alignY = .Center
            .margin.x          = 0
            .margin.z          = metrics.dialog_BtnPadding
            .sigPressed        += func|window|(_) { window.chooseUnlockKeyFiles() }
        }

        with result.readOnly = CheckButton.create(result.options, appStrings().ui_ReadOnly)
        {
            .layoutSpec.alignY = .Center
        }

        with result.mount = PushButton.create(result.panel, appStrings().ui_Mount, form: .Strong)
        {
            .sigPressed += func|window|(_) { window.mountContainer() }
        }

        return result
    }

    // Returns the height of the card at `width`: the head, the password and the line of choices.
    mtd measureHeight(width: f32)->f32
    {
        let formWidth = Math.max(0, width - VaultRow.TextX - RowOutset)
        let formTop   = VaultRow.Height - .panel.themeMetrics().dialog_BtnPadding
        let form      = Math.ceil(.form.measure(Math.Point{formWidth, 0}).preferred.y)
        let options   = .panel.themeMetrics().btnPush_Height
        return formTop + form + OptionsGap + options + BottomPadding
    }

    // Lays the card over `rect` of the list and arranges what it holds.
    mtd place(rect: Math.Rectangle)
    {
        .panel.arrange(rect)

        let width     = rect.width
        let formWidth = Math.max(0, width - VaultRow.TextX - RowOutset)
        let formTop   = VaultRow.Height - .panel.themeMetrics().dialog_BtnPadding
        let formH     = Math.ceil(.form.measure(Math.Point{formWidth, 0}).preferred.y)
        let lineTop   = formTop + formH + OptionsGap
        let lineH     = .panel.themeMetrics().btnPush_Height

        .header.arrange(Math.Rectangle{0, 0, width, VaultRow.Height})
        .form.arrange(Math.Rectangle{VaultRow.TextX, formTop, formWidth, formH})

        let mount = .mount.measure({}).preferred
        .mount.arrange(Math.Rectangle{width - RowOutset - mount.x, lineTop, mount.x, lineH})

        let optionsWidth = Math.max(0, .mount.position.x - VaultRow.TextX - .panel.themeMetrics().dialog_BtnPadding)
        .options.arrange(Math.Rectangle{VaultRow.TextX, lineTop, optionsWidth, lineH})
        .options.computeLayout()
    }

    // Says the card again in the language now active.
    mtd retranslate(keyFileCount: u64)
    {
        let texts = appStrings()
        .form.setRowLabel(0, texts.ui_Password)
        .password.setPlaceholder(texts.ui_ContainerPassword)
        .driveLabel.setText(texts.ui_Drive)
        .readOnly.setText(texts.ui_ReadOnly)
        .mount.setText(texts.ui_Mount)
        .setKeyFileCount(keyFileCount)
    }

    // Says how many key files the access states, on the link that chooses them.
    mtd setKeyFileCount(count: u64)
    {
        let texts = appStrings()
        if count do
            .keyFiles.setText(Format.toString(texts.ui_KeyFilesCount, count))
        else do
            .keyFiles.setText(texts.ui_KeyFilesLink)
        .options.computeLayout()
    }
}
