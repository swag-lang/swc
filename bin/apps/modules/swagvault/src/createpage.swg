using Core, Gui, Pixel

// The page that makes a new vault: a calm form under its title, the capacity set large.
//
// It asks where the container goes, how much it holds, and the password that opens it, the two
// passwords side by side because they are one answer given twice. Key files are chosen in a box of
// their own, so the form keeps to what every vault needs. The primary action ends the page, beside
// the quiet way back.
struct CreatePage
{
    using wnd: Wnd

    late
    {
        window:       *MainWindow
        column:       *StackLayoutCtrl
        form:         *FormLayoutCtrl
        path:         *EditBox
        browse:       *PushButton
        size:         *EditBox
        unit:         *Tab
        passwordForm: *FormLayoutCtrl
        confirmForm:  *FormLayoutCtrl
        password:     *PasswordEdit
        confirm:      *PasswordEdit
        actions:      *Wnd
        keyFiles:     *IconButton
        cancel:       *PushButton
        createAction: *PushButton
    }

    head: PageHead
}

// Rows of the form, in the order `CreatePage.create` adds them.
enum CreateRow
{
    Location      // Container file to create, and the way to browse to it.
    Capacity      // Fixed size and its unit.
    Passwords     // Password and its confirmation, side by side.
}

impl CreatePage
{
    const SizeFontSize = 22'u32     // Size of the capacity, the one figure of the form.
    const SizeWidth    = 140'f32
    const SizeHeight   = 44'f32
    const RowSpacing   = 24'f32
    const PairSpacing  = 16'f32

    // Creates the page in `window`, hidden.
    func create(window: *MainWindow)->*CreatePage
    {
        with let result = Wnd.create'CreatePage(window, "vault.create")
        {
            .window          = window
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .hide()
        }

        let texts = appStrings()
        result.column = createPageColumn(result)
        result.head   = PageHead.create(result.column, texts.ui_NewVault, texts.ui_CreateHelp)
        result.head.back.sigPressed += func|window|(_) { window.showPage(.List) }

        result.createForm()
        result.createActions()
        result.retranslate()
        return result
    }

    // Creates the three rows of the form: where, how much, and what opens it.
    private mtd createForm()
    {
        let texts = appStrings()

        var options: FormLayoutOptions
        options.labelFlags = .SecondaryText
        options.rowSpacing = RowSpacing
        with .form = FormLayoutCtrl.create(.column, options)
        {
            .margin.y = PageHeadGap
        }

        with .path = .form.addTextField(texts.ui_Location, placeholder: "C:\\path\\private")
        {
            .updateFlags(.AcceptFileDrop)
            setMachineFont(me.path)
            .sigTextChanged += func|window = me.window|(_) { window.refreshActions() }
            .sigSubmitted   += func|window = me.window|(_) { window.submitCreate() }
        }

        with .browse = .form.addRowAction(texts.ui_Browse)
        {
            .sigPressed += func|page = me|(_) { page.window.chooseContainer(page.path, true) }
        }

        // The capacity is the one figure the reader decides here, so it is set large, with its
        // unit beside it as two words to choose between.
        with let capacity = StackLayoutCtrl.create(.form, .Left, Math.Rectangle{0, 0, 0, SizeHeight})
        {
            .backgroundStyle = .Transparent
            .spacing         = PairSpacing
        }

        with .size = EditBox.create(capacity, "256", Math.Rectangle{0, 0, SizeWidth, SizeHeight})
        {
            .setUnsignedIntegerRange(1, 1024 * 1024)
            .style.setFont(me.theme().createDefaultFont(SizeFontSize), .Regular)
            .sigTextChanged += func|window = me.window|(_) { window.refreshActions() }
            .sigSubmitted   += func|window = me.window|(_) { window.submitCreate() }
        }

        with .unit = Tab.create(capacity, {})
        {
            .layoutSpec.alignY = .Center
            .setForm(.Flat)
            .setForms(.Transparent, .Flat, .None)
            .setLayout(.Content)
            discard .addItem(texts.ui_UnitMiB)
            discard .addItem(texts.ui_UnitGiB)
            .setSelectedIndex(0)
        }

        discard .form.addField(texts.ui_Capacity, capacity)

        // One answer given twice reads as one row.
        with let pair = StackLayoutCtrl.create(.form, .HorizontalFit)
        {
            .backgroundStyle = .Transparent
            .spacing         = PairSpacing
        }

        var pairOptions: FormLayoutOptions
        pairOptions.labelFlags = .SecondaryText
        .passwordForm = FormLayoutCtrl.create(pair, pairOptions)
        .confirmForm  = FormLayoutCtrl.create(pair, pairOptions)
        .password     = .passwordForm.addPasswordField(texts.ui_Password, placeholder: texts.ui_OptionalPassword)
        .confirm      = .confirmForm.addPasswordField(texts.ui_Confirm, placeholder: texts.ui_EnterAgain)
        for edit in [.password, .confirm]
        {
            edit.sigChanged   += func|window = me.window|(_) { window.refreshActions() }
            edit.sigSubmitted += func|window = me.window|(_) { window.submitCreate() }
        }

        discard .form.addField("", pair)
    }

    // Creates the line of actions that ends the page: the key files at its start, the way back and
    // the primary action at its end.
    private mtd createActions()
    {
        let texts = appStrings()
        with .actions = Wnd.create'Wnd(.column, Math.Rectangle{0, 0, 0, .themeMetrics().btnPush_Height})
        {
            .backgroundStyle = .Transparent
            .margin.y        = PageHeadGap

            // Reaches into the margin by the air of a quiet word, so the words of the first one
            // stand on the edge of the column.
            .margin.x = -me.themeMetrics().btnIcon_Padding
        }

        with .keyFiles = createQuietLink(.actions, texts.ui_AddKeyFilesLink)
        {
            .sigPressed += func|window = me.window|(_) { window.chooseCreateKeyFiles() }
        }

        with .cancel = PushButton.create(.actions, strings().dlg_Cancel, form: .Flat)
        {
            .sigPressed += func|window = me.window|(_) { window.showPage(.List) }
        }

        with .createAction = PushButton.create(.actions, texts.ui_CreateVault, form: .Strong)
        {
            .sigPressed += func|window = me.window|(_) { window.createContainer() }
        }
    }

    // Says everything the page wrote at construction again, in the language now active.
    mtd retranslate()
    {
        let texts = appStrings()
        .head.retranslate(texts.ui_NewVault, texts.ui_CreateHelp)
        .form.setRowLabel(cast(u64, CreateRow.Location), texts.ui_Location)
        .form.setRowLabel(cast(u64, CreateRow.Capacity), texts.ui_Capacity)
        .passwordForm.setRowLabel(0, texts.ui_Password)
        .confirmForm.setRowLabel(0, texts.ui_Confirm)
        .password.setPlaceholder(texts.ui_OptionalPassword)
        .confirm.setPlaceholder(texts.ui_EnterAgain)
        .browse.setText(texts.ui_Browse)
        .unit.setItemName(0, texts.ui_UnitMiB)
        .unit.setItemName(1, texts.ui_UnitGiB)
        .cancel.setText(strings().dlg_Cancel)
        .createAction.setText(texts.ui_CreateVault)
        .setKeyFileCount(.window.createKeyFiles.count)
        .arrange()
    }

    // Says how many key files the new vault will need, on the link that chooses them.
    mtd setKeyFileCount(count: u64)
    {
        let texts = appStrings()
        if count do
            .keyFiles.setText(Format.toString(texts.ui_KeyFilesCount, count))
        else do
            .keyFiles.setText(texts.ui_AddKeyFilesLink)
        .arrangeActions()
    }

    // Places the column in the page, then the actions on their line.
    mtd arrange()
    {
        // A window is laid out as soon as it is made, before its parts exist.
        if .createAction == null do
            return
        placePageColumn(me, .column)
        .arrangeActions()
    }

    // Stands the key files at the start of the line, and the way back and the primary action at its end.
    mtd arrangeActions()
    {
        let room = .actions.clientRect()
        let gap  = .themeMetrics().dialog_BtnPadding * 2

        let keyFiles = .keyFiles.measure({}).preferred
        let cancel   = .cancel.measure({}).preferred
        let create   = .createAction.measure({}).preferred
        .keyFiles.arrange(Math.Rectangle{room.x, room.y, keyFiles.x, room.height})
        .createAction.arrange(Math.Rectangle{room.right() - create.x, room.y, create.x, room.height})
        .cancel.arrange(Math.Rectangle{.createAction.position.x - gap - cancel.x, room.y, cancel.x, room.height})
    }
}

impl IWnd for CreatePage
{
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        .arrange()
    }
}
