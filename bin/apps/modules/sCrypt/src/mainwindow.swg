using Core, Gui, Pixel

internal enum AppState
{
    Ready
    Creating
    Mounting
    Mounted
    Unmounting
}

internal enum OperationKind
{
    None
    Create
    Mount
    Unmount
}

// Emphasis of the status line, from what the latest step left behind.
internal enum StatusTone
{
    Idle        // Nothing is running and nothing has failed.
    Active      // Work is running, or a drive is mounted.
    Stopped     // The latest operation stopped.
}

// What the status line is currently reporting.
//
// The line is named rather than written, so a language switch can say the same thing
// again without the window having kept a copy of the sentence. Each value carries one
// tone, which is why `setStatus` takes no second argument.
internal enum StatusMessage
{
    Ready              // Nothing has run yet, or the last operation finished cleanly.
    Randomizing        // The container is being filled with random bytes; `statusProgress` says how far.
    StopRequested      // The user asked the running creation to stop.
    CreateCanceled     // Creation stopped on request and left nothing behind.
    StartingDriver     // The portable filesystem driver is starting.
    Unmounting         // The drive is being synchronized and unmounted.
    CreateStopped      // Container creation stopped.
    Created            // The container was created and is ready to mount.
    MountStopped       // Mounting stopped.
    Mounted            // A drive is mounted; `statusDrive` names its letter.
    Unmounted          // The drive was unmounted safely.
}

// Rows of the "create a new vault" form, in the order `createNewVaultCard` adds them.
//
// The form owns the labels it creates, so re-labelling one after a language switch names
// its row. Keep these next to the builder: they are two halves of one decision.
internal enum CreateRow
{
    Path         // Container file to create.
    Capacity     // Fixed size and its unit.
    Password     // Password protecting the container.
    Confirm      // Same password, entered again.
}

// Rows of the "mount an existing vault" form, in the order `createMountVaultCard` adds them.
internal enum MountRow
{
    Path         // Container file to open.
    Password     // Password unlocking the container.
    Drive        // Drive letter the volume appears on.
}

// Long operation running outside the UI thread. Only one runs at a time, and the window
// polls `job` with `timer` until the result is ready to be reported.
struct VaultOperation
{
    job:      Jobs.Job           // Worker scheduled for `kind`.
    kind:     OperationKind      // Work the job performs, or `None` while the window is idle.
    timer:    #null *Timer       // Polls the job while it runs.
    error:    #null any          // Failure captured by the job, or null when it succeeded.
    path:     String             // Container file the operation acts on.
    mount:    String             // Drive letter requested by a mount operation.
    size:     u64                // Container size requested by a create operation.
    password: Array'u8           // Password copy owned by the operation and wiped when it ends.
    progress: VolumeProgress     // What the job has done, and the way to ask it to stop.
}

// Owns the complete application state. The UI thread owns this object; long
// operations use `operation` and report their result back through the timer.
struct MainWindow
{
    using wnd: Wnd

    // Text of the header, kept so a language switch can say it again.
    #[Swag.Late]
    {
        badge:    *Label
        subtitle: *Label
    }

    // Controls of the "create a new vault" card.
    #[Swag.Late]
    {
        createPath:      *EditBox
        createSize:      *EditBox
        createUnit:      *ComboBox
        createPassword:  *PasswordEdit
        confirmPassword: *PasswordEdit
        createButton:    *PushButton
        browseCreate:    *PushButton
    }

    // Controls of the "mount an existing vault" card.
    #[Swag.Late]
    {
        mountPath:     *EditBox
        mountPassword: *PasswordEdit
        drive:         *ComboBox
        mountButton:   *PushButton
        unmountButton: *PushButton
        browseMount:   *PushButton
    }

    // The single status line displayed above the footer, the glyph whose color reports its tone,
    // and the spinner that replaces the glyph while work runs. The text and the glyph are written
    // only through `setStatus`, the spinner only through `showBusy`.
    #[Swag.Late]
    {
        statusView:     *Wnd
        status:         *Label
        statusIcon:     *Label
        statusBusy:     *Spinner
        languageChoice: *ComboBox
    }

    // The two cards, kept whole so a language switch can re-label their headings.
    createCard: VaultCard = undefined
    mountCard:  VaultCard = undefined

    fileDlgState: FileDlgState
    mounted:      WinFsp.MountedVolume
    state:        AppState
    shuttingDown: bool
    operation:    VaultOperation

    // What the status line says, plus the two values its wording interpolates: the drive
    // letter of the mounted message and the percentage of the randomizing one.
    statusMessage:  StatusMessage
    statusDrive:    String
    statusProgress: s32

    // Language tag applied at start, or empty to follow the language of the account.
    //
    // It holds [[Gui.ReferenceLanguage]] until the user picks something else: sCrypt is an
    // English application that speaks other languages on request, not one that guesses.
    language: String
}

internal func caughtMessage(err: #null any)->string
{
    switch err
    {
    case Error:            return (cast(Error) err).message orelse appStrings().msg_OperationStopped
    case Swag.SystemError: return (cast(Swag.SystemError) err).message orelse appStrings().msg_SystemError
    }

    return appStrings().msg_OperationStopped
}

// Whether an operation stopped because the user asked it to, rather than because something
// about the container or the system stopped it.
internal func isCanceledError(err: #null any)->bool
{
    switch err
    {
    case Error as volumeError: return volumeError.kind == .Canceled
    }

    return false
}

internal func runMainWindowOperation(data: #null *void)
{
    let window = cast(*MainWindow) (data!)
    window.runOperation()
}

// Sets a control in the fixed-width theme family.
//
// A path, a capacity, a unit, and a drive letter are read by the system, not by a reader, so
// they are set like the compiler sets a name it knows and never look like prose.
internal func setMachineFont(wnd: *Wnd)
{
    let theme = wnd.theme()
    wnd.style.setFont(theme.createDefaultFontFS(theme.metrics.defaultFixedFontSize), .Regular)
}

impl MainWindow
{
    func create(parent: *Wnd)->*MainWindow
    {
        let result  = Wnd.create'MainWindow(parent, "sCrypt.mainWindow")
        let surface = result.surface!
        surface.setView(result)
        surface.minSize        = {1100, 790}
        result.backgroundStyle = .View
        result.language        = ReferenceLanguage

        // One accent rule across the top identifies every standard Swag application surface.
        Separator.create(result, .Top, .Accent)

        result.createHeader()
        result.createFooter()

        // Two equal columns: create on the left, mount on the right.
        let cards = GridLayoutCtrl.create(result, 2, 1)
        with cards
        {
            .dockStyle         = .Center
            .margin            = {32, 16, 32, 16}
            .horizontalSpacing = 24
            .setColumnTrack(0, .Fraction, 1)
            .setColumnTrack(1, .Fraction, 1)
            .setRowTrack(0, .Fraction, 1)
            .setCell(result.createNewVaultCard(cards), 0, 0)
            .setCell(result.createMountVaultCard(cards), 1, 0)
        }

        result.watchFormState()
        result.applyLayout()
        cards.computeLayout()
        result.setState(.Ready)
        result.setStatus(.Ready)

        // The window opens on the first thing there is to fill in, so it can be driven from the
        // keyboard alone: Tab walks the create card, then the mount card, then the language.
        result.setInitialFocus()
        return result
    }

    // Follows every field an action depends on, so the two buttons are never live on a form
    // that cannot answer for them.
    mtd watchFormState()
    {
        mtd onEdit(edit: *EditBox)
        {
            edit.sigTextChanged += func|window = me|(box)
            {
                discard box
                window.refreshActions()
            }
        }

        mtd onPassword(edit: *PasswordEdit)
        {
            edit.sigChanged += func|window = me|(box)
            {
                discard box
                window.refreshActions()
            }
        }

        .onEdit(.createPath)
        .onEdit(.createSize)
        .onEdit(.mountPath)
        .onPassword(.createPassword)
        .onPassword(.confirmPassword)
        .onPassword(.mountPassword)

        .drive.sigChanged += func|window = me|(combo, index)
        {
            discard combo
            discard index
            window.refreshActions()
        }

        .watchSubmit()
    }

    // Follows Enter in every field, so a card can be answered from the keyboard.
    //
    // Enter presses the action of the card the field belongs to, not one action for the whole
    // surface: this window carries two dominant actions, and the field being typed in is what says
    // which of the two was meant.
    mtd watchSubmit()
    {
        mtd onCreateEdit(edit: *EditBox)
        {
            edit.sigSubmitted += func|window = me|(box)
            {
                discard box
                window.submitCreate()
            }
        }

        mtd onCreatePassword(edit: *PasswordEdit)
        {
            edit.sigSubmitted += func|window = me|(box)
            {
                discard box
                window.submitCreate()
            }
        }

        .onCreateEdit(.createPath)
        .onCreateEdit(.createSize)
        .onCreatePassword(.createPassword)
        .onCreatePassword(.confirmPassword)

        .mountPath.sigSubmitted += func|window = me|(box)
        {
            discard box
            window.submitMount()
        }

        .mountPassword.sigSubmitted += func|window = me|(box)
        {
            discard box
            window.submitMount()
        }
    }

    // Creates the container when the create form holds everything it needs.
    //
    // A form that cannot answer stays silent instead of opening a box: the button is already down
    // for the same reason, so Enter says exactly what the button says.
    mtd submitCreate()
    {
        if .state != .Ready or !.canCreate() do
            return
        .createContainer()
    }

    // Mounts the drive when the mount form holds everything it needs.
    mtd submitMount()
    {
        if .state != .Ready or !.canMount() do
            return
        .mountContainer()
    }

    mtd createHeader()
    {
        // The header is as tall as the two rows it holds, so a wrapped explanation is not
        // cut off by a height calibrated on the shortest of the shipped languages.
        let header = StackLayoutCtrl.create(me, .Top)
        header.dockStyle = .Top
        header.margin    = {32, 20, 32, 0}
        header.spacing   = 4

        // The badge shares the line of the product name rather than floating between the name
        // and its explanation, so the header reads as two rows instead of three.
        let titleRow = Wnd.create'Wnd(header, {0, 0, 0, 44})
        titleRow.dockStyle = .Top

        // The badge is a compact claim about the product, and it is measured rather than
        // set: a hand-tuned width clips it as soon as the theme font or the language changes.
        .badge           = Label.create(titleRow, appStrings().ui_Badge, {}, null, .SecondaryText)
        .badge.dockStyle = .Right
        .badge.setTextAlignment(.Right, .Center)
        .badge.style.setFont(.theme().createDefaultFontFS(12, .Bold), .Regular)

        let titleFont = .theme().createDefaultFont(34, .Bold)
        let title     = Label.create(titleRow, "sCrypt")
        title.dockStyle = .Center
        title.setTextAlignment(.Left, .Center)
        title.style.setFont(titleFont, .Regular)

        // The row is as tall as the line box of the name. A hand-tuned height clips it, and by a
        // fraction of a pixel: enough to cut a descender, not enough to be noticed until the name
        // is set in another face.
        titleRow.resize(titleRow.position.width, Math.max(titleRow.position.height, titleFont.height))

        .subtitle           = Label.create(header, appStrings().ui_Subtitle, {}, null, .WordWrap | .SecondaryText | .AutoHeight)
        .subtitle.dockStyle = .Top
        .subtitle.setTextAlignment(.Left, .Top)
        titleRow.applyLayout()
        header.computeLayout()
    }

    mtd createFooter()
    {
        // The language picker rides the credit line rather than claiming a row of its own:
        // on a surface this compact, a row costs more than the setting is worth. The row is
        // as tall as the picker it carries, so the field keeps the size every other field of
        // the window has instead of being squeezed into a line of prose.
        let footerRow = Wnd.create'Wnd(me, {0, 0, 0, .themeMetrics().comboBox_Height})
        footerRow.dockStyle = .Bottom
        footerRow.margin    = {32, 0, 32, 12}

        .languageChoice            = ComboBox.create(footerRow, {}, flags: .Flat)
        .languageChoice.dockStyle  = .Right
        .languageChoice.sigChanged += func|window = me|(combo, index)
        {
            discard combo
            window.chooseLanguage(index)
        }

        let credit = Label.create(footerRow, "WinFsp — Windows File System Proxy, Copyright (C) Bill Zissimopoulos — github.com/winfsp/winfsp", {}, null, .SecondaryText)
        credit.dockStyle = .Center
        credit.setTextAlignment(.Left, .Center)
        .fillLanguageChoice()
        footerRow.applyLayout()

        // The status line is raised off the ground by its own fill. A border around it would
        // draw a third box on a surface that already reads without one.
        .statusView                 = Wnd.create'Wnd(me, {0, 0, 0, 52})
        .statusView.dockStyle       = .Bottom
        .statusView.margin          = {32, 0, 32, 12}
        .statusView.backgroundStyle = .Window
        .statusView.padding         = {20, 8, 20, 8}

        .statusIcon           = Label.create(.statusView, "", {0, 0, 24})
        .statusIcon.dockStyle = .Left
        .statusIcon.margin.z  = 12

        // The spinner takes the glyph's place rather than a slot of its own: it is the same
        // 24-pixel square, and a docked window that is hidden takes no room, so the status text
        // starts at the same column whether work is running or not.
        .statusBusy           = Spinner.create(.statusView, {0, 0, 24, 24})
        .statusBusy.dockStyle = .Left
        .statusBusy.margin.z  = 12
        .statusBusy.hide()

        .status           = Label.create(.statusView, "")
        .status.dockStyle = .Center
        .status.setTextAlignment(.Left, .Center)
        .statusView.applyLayout()
    }

    // Puts the spinner in the glyph's place while an operation runs, and takes it back when the
    // operation ends. A spinner is the honest report for work whose remaining time is unknown;
    // creation additionally writes its percentage onto the status line.
    mtd showBusy(busy: bool)
    {
        if .statusBusy.isLocallyVisible() == busy do
            return
        .statusIcon.show(!busy)
        .statusBusy.show(busy)
        .statusView.applyLayout()
    }

    // Fills the language picker with the system entry and every registered language.
    //
    // A language is named in its own words, so the entries are not translated; only the
    // system entry is, since it names a rule rather than a language.
    mtd fillLanguageChoice()
    {
        .languageChoice.clear()
        .languageChoice.addItem(appStrings().ui_LanguageSystem)
        for &one in Gui.languages() do
            .languageChoice.addItem(one.nativeName.toString())
        .languageChoice.setSelectedIndex(.languageChoiceIndex(), notify: false)
    }

    // Returns the picker entry matching the persisted choice.
    mtd languageChoiceIndex()->u32
    {
        if .language.isEmpty() do
            return 0
        for &one, [index] in Gui.languages() where one.tag == .language do
            return cast(u32) index + 1
        return 0
    }

    // Applies the language the user picked and remembers it across runs.
    mtd chooseLanguage(index: u32)
    {
        let all = Gui.languages()
        .language = index != 0 and index <= cast(u32) @countof(all) ? all[index - 1].tag : String.from("")
        .applyLanguage()
    }

    // Applies the persisted language, or the language of the account when none was picked.
    mtd applyLanguage()
    {
        let tag = .language.isEmpty() ? Gui.systemLanguage() : .language.toString()
        catch .app().setLanguage(tag)
    }

    // Reports the outcome of the latest step on the single status line.
    //
    // One glyph, three colors: the theme atlas has no monochrome success or failure glyph, and
    // borrowing a colored one would put a third hue on a two-color surface. The color alone
    // separates a line that is waiting from one that reports work, or one that stopped.
    mtd setStatus(message: StatusMessage)
    {
        .statusMessage = message
        .refreshStatus()
    }

    // Writes the current status message on the line in the active language.
    mtd refreshStatus()
    {
        let colors = .themeColors()

        var glyphColor, textColor: Color = undefined
        switch #complete .statusTone()
        {
        case .Idle:
            glyphColor = colors.label_TextLight
            textColor  = colors.label_TextLight

        case .Active:
            glyphColor = colors.hilight
            textColor  = colors.label_Text

        case .Stopped:
            glyphColor = colors.error
            textColor  = colors.error
        }

        var glyph = .theme().icon(ThemeIcons.About, 20)
        glyph.color = glyphColor
        .statusIcon.setIcon(glyph)
        .status.setTextColor(textColor)
        .status.setText(.statusText())
    }

    // Returns the emphasis the current status message carries.
    mtd statusTone()->StatusTone
    {
        switch #complete .statusMessage
        {
        case .Randomizing, .StopRequested, .StartingDriver, .Unmounting, .Mounted: return .Active
        case .CreateStopped, .MountStopped:                                        return .Stopped
        case .Ready, .CreateCanceled, .Created, .Unmounted:                        return .Idle
        }
    }

    // Returns the current status message in the active language.
    mtd statusText()->String
    {
        let texts = appStrings()
        switch #complete .statusMessage
        {
        case .Ready:          return String.from(texts.msg_Ready)
        case .Randomizing:    return Format.toString(texts.msg_Randomizing, .statusProgress)
        case .StopRequested:  return String.from(texts.msg_StopRequested)
        case .CreateCanceled: return String.from(texts.msg_CreateCanceled)
        case .StartingDriver: return String.from(texts.msg_StartingDriver)
        case .Unmounting:     return String.from(texts.msg_Unmounting)
        case .CreateStopped:  return String.from(texts.msg_CreateStopped)
        case .Created:        return String.from(texts.msg_Created)
        case .MountStopped:   return String.from(texts.msg_MountStopped)
        case .Mounted:        return Format.toString(texts.msg_Mounted, .statusDrive)
        case .Unmounted:      return String.from(texts.msg_Unmounted)
        }
    }

    mtd createNewVaultCard(parent: *GridLayoutCtrl)->*Wnd
    {
        let card = VaultCard.create(parent, appStrings().ui_CreateCardTitle, appStrings().ui_CreateCardHelp)
        let form = card.form
        .createCard = card

        .createPath = form.addTextField(appStrings().ui_ContainerFile, placeholder: "C:\\path\\private.scrypt", icon: .theme().icon(ThemeIcons.OpenFile, 17))
        setMachineFont(.createPath)
        .browseCreate            = form.addRowAction(appStrings().ui_Browse, .theme().icon(ThemeIcons.OpenFile, 16))
        .browseCreate.sigPressed += func|window = me|(btn)
        {
            discard btn
            window.chooseContainer(window.createPath, true)
        }

        .createSize = form.addTextField(appStrings().ui_FixedCapacity, "256")
        .createSize.setUnsignedIntegerRange(1, 1024 * 1024)
        setMachineFont(.createSize)

        // The multiplier read by `containerSize` follows this order.
        .createUnit = form.addRowChoice()
        .createUnit.addItem("MiB")
        .createUnit.addItem("GiB")
        .createUnit.setSelectedIndex(0, notify: false)
        setMachineFont(.createUnit)

        .createPassword  = form.addPasswordField(appStrings().ui_Password, placeholder: appStrings().ui_RequiredPassword)
        .confirmPassword = form.addPasswordField(appStrings().ui_ConfirmPassword, placeholder: appStrings().ui_EnterAgain)

        // Creation is the one operation long enough to be worth stopping, so its own button
        // becomes the way out of it. A second control would sit dead on the card the rest of
        // the time, and the card already has one dominant action.
        //
        // It carries no width for that very reason: the caption changes with the state and
        // with the language, so the layout pass reads it from the button rather than from a
        // number tuned on one wording.
        .createButton = PushButton.create(card.actions, appStrings().ui_CreateVault, {0, 0, 0, 36}, form: .Strong)
        .createButton.setIcon(.theme().icon(ThemeIcons.SaveAs, 18))
        .createButton.sigPressed += func|window = me|(btn)
        {
            discard btn
            if window.state == .Creating do
                window.stopCreating()
            else do
                window.createContainer()
        }

        card.actions.computeLayout()
        card.endForm()
        return card.panel
    }

    mtd createMountVaultCard(parent: *GridLayoutCtrl)->*Wnd
    {
        let card = VaultCard.create(parent, appStrings().ui_MountCardTitle, appStrings().ui_MountCardHelp)
        let form = card.form
        .mountCard = card

        .mountPath = form.addTextField(appStrings().ui_ContainerFile, placeholder: appStrings().ui_ExistingContainer, icon: .theme().icon(ThemeIcons.OpenFile, 17))
        setMachineFont(.mountPath)
        .browseMount            = form.addRowAction(appStrings().ui_Browse, .theme().icon(ThemeIcons.OpenFile, 16))
        .browseMount.sigPressed += func|window = me|(btn)
        {
            discard btn
            window.chooseContainer(window.mountPath, false)
        }

        .mountPassword = form.addPasswordField(appStrings().ui_Password, placeholder: appStrings().ui_ContainerPassword)

        // The lifetime of the drive belongs to the letter that carries it, so it is said under
        // that field rather than as a loose paragraph at the bottom of the card.
        .drive = form.addChoiceField(appStrings().ui_DriveLetter, help: appStrings().ui_DriveHelp)
        setMachineFont(.drive)

        // Windows keeps A and B for floppies and C for the system disk, so the letters a
        // user expects come first and the unusual ones stay available further down.
        let available = File.availableDriveLetters()
        for letter in available where letter >= 'D' do
            .drive.addItem(Format.toString("%:", letter))
        for letter in available where letter < 'D' do
            .drive.addItem(Format.toString("%:", letter))
        if .drive.items.count do
            .drive.setSelectedIndex(0, notify: false)

        .unmountButton = PushButton.create(card.actions, appStrings().ui_Unmount, {0, 0, 0, 36})
        .unmountButton.setIcon(.theme().icon(ThemeIcons.Stop, 18))
        .unmountButton.sigPressed += func|window = me|(btn)
        {
            discard btn
            window.unmountContainer()
        }

        .mountButton = PushButton.create(card.actions, appStrings().ui_MountDrive, {0, 0, 0, 36}, form: .Strong)
        .mountButton.setIcon(.theme().icon(ThemeIcons.Play, 18))
        .mountButton.sigPressed += func|window = me|(btn)
        {
            discard btn
            window.mountContainer()
        }

        card.actions.computeLayout()
        card.endForm()
        return card.panel
    }

    mtd showError(message: string, err: #null any = null)
    {
        var detail = String.from(message)
        if err != null do
            detail = Format.toString("%\n\n%", message, caughtMessage(err))
        MessageDlg.error(.surface!, detail)
    }

    // Whether the create form holds everything a container needs.
    //
    // The capacity is not read here: it carries a default and validates as it is typed, so
    // the only way to leave it unusable is to empty it.
    mtd canCreate()->bool
    {
        return @countof(.createPath.text()) != 0 and
               @countof(.createSize.text()) != 0 and
               !.createPassword.isEmpty() and
               !.confirmPassword.isEmpty()
    }

    // Whether the mount form holds everything a drive needs.
    mtd canMount()->bool
    {
        return @countof(.mountPath.text()) != 0 and
               !.mountPassword.isEmpty() and
               !.selectedMountPoint().isEmpty()
    }

    // Puts each action in step with what its form holds.
    //
    // A button that cannot work says so by being down, rather than by accepting the press
    // and answering with a box: the reader learns what is missing before acting, not after.
    // What the form cannot know — a name already taken, a password that does not match, a
    // capacity out of range — is still reported when the operation runs.
    mtd refreshActions()
    {
        if .state != .Ready do
            return
        .createButton.enable(.canCreate())
        .mountButton.enable(.canMount())
    }

    mtd setState(state: AppState)
    {
        .state = state
        let ready    = state == .Ready
        let mounted  = state == .Mounted
        let creating = state == .Creating

        // The create button stays live through creation, because during creation it is what stops
        // it. It is put in its new state before the forms go down, so the keyboard a disabled form
        // hands on lands on the one control that still answers rather than walking to the far end
        // of the surface.
        .createButton.enable(creating or (ready and .canCreate()))
        .createButton.setText(creating ? appStrings().ui_StopCreating : appStrings().ui_CreateVault)
        .createButton.setIcon(.theme().icon(creating ? ThemeIcons.Stop : ThemeIcons.SaveAs, 18))

        // Disabling a form disables every field and trailing control it owns.
        .createCard.form.enable(ready)
        .mountCard.form.enable(ready)
        .mountButton.enable(ready and .canMount())
        .unmountButton.enable(mounted)
    }

    // Says everything the window said at construction, in the language now active.
    //
    // Only text set once by hand needs this: the buttons and the wrapped paragraphs
    // re-measure themselves from the new wording, so the surface re-arranges around what
    // the language actually costs instead of around the widths English needed.
    mtd retranslate()
    {
        let texts = appStrings()
        .surface?.setTitle(texts.ui_WindowTitle)

        .badge.setText(texts.ui_Badge)
        .subtitle.setText(texts.ui_Subtitle)

        .createCard.setTexts(texts.ui_CreateCardTitle, texts.ui_CreateCardHelp)
        .createCard.form.setRowLabel(cast(u64) CreateRow.Path, texts.ui_ContainerFile)
        .createCard.form.setRowLabel(cast(u64) CreateRow.Capacity, texts.ui_FixedCapacity)
        .createCard.form.setRowLabel(cast(u64) CreateRow.Password, texts.ui_Password)
        .createCard.form.setRowLabel(cast(u64) CreateRow.Confirm, texts.ui_ConfirmPassword)
        .createPassword.setPlaceholder(texts.ui_RequiredPassword)
        .confirmPassword.setPlaceholder(texts.ui_EnterAgain)
        .browseCreate.setText(texts.ui_Browse)

        .mountCard.setTexts(texts.ui_MountCardTitle, texts.ui_MountCardHelp)
        .mountCard.form.setRowLabel(cast(u64) MountRow.Path, texts.ui_ContainerFile)
        .mountCard.form.setRowLabel(cast(u64) MountRow.Password, texts.ui_Password)
        .mountCard.form.setRowLabel(cast(u64) MountRow.Drive, texts.ui_DriveLetter)
        .mountCard.form.setRowHelp(cast(u64) MountRow.Drive, texts.ui_DriveHelp)
        .mountPath.setPlaceholder(texts.ui_ExistingContainer)
        .mountPassword.setPlaceholder(texts.ui_ContainerPassword)
        .browseMount.setText(texts.ui_Browse)
        .mountButton.setText(texts.ui_MountDrive)
        .unmountButton.setText(texts.ui_Unmount)

        // The create button says what it does *now*, so its caption is the state's to write,
        // not this method's: during a creation it reads "stop", not "create".
        .setState(.state)
        .fillLanguageChoice()
        .refreshStatus()

        .applyLayout()
        .createCard.endForm()
        .mountCard.endForm()
        .createCard.actions.computeLayout()
        .mountCard.actions.computeLayout()
        .invalidate()
    }

    mtd chooseContainer(target: *EditBox, create: bool)
    {
        var options: FileDlgOptions
        options.state             = &.fileDlgState
        options.mode              = create ? .CreateFile : .SelectFile
        options.title             = create ? appStrings().dlg_TitleCreate : appStrings().dlg_TitleOpen
        options.confirmButtonText = create ? appStrings().dlg_BtnCreate : appStrings().dlg_BtnOpen
        options.initialName       = create ? "volume.scrypt" : ""
        options.filters.add({"sCrypt encrypted container (*.scrypt)", ".scrypt"})
        options.shortcuts.add({Env.SpecialDirectory.Desktop, appStrings().ui_Desktop})
        options.shortcuts.add({Env.SpecialDirectory.UserDocuments, "Documents"})

        let dialog = FileDlg.create(.surface!, options)
        if dialog.doModal() == Dialog.BtnOk do
            target.setText(dialog.selectedPath())
    }

    mtd containerSize()->u64 fail
    {
        let text   = .createSize.text()
        let parsed = catch StrConv.parseU64(text) as parseError
        if parseError != null or parsed.ovf or parsed.eat != @countof(text) or !parsed.value do
            failWith(appStrings().msg_SizeInvalid, .InvalidInput)

        let multiplier = .createUnit.selectedIndex == 0 ? 1024'u64 * 1024 : 1024'u64 * 1024 * 1024
        if parsed.value > Swag.U64.Max / multiplier do
            failWith(appStrings().msg_SizeTooLarge, .InvalidInput)

        let result = parsed.value * multiplier
        if result < MinimumSize do
            failWith(Format.toString(appStrings().msg_SizeMinimum, (MinimumSize + 1024 * 1024 - 1) / (1024 * 1024)), .InvalidInput)
        return result
    }

    mtd selectedMountPoint()->String
    {
        let item = .drive.selectedItem()
        return item ? String.from(item!.name.raw) : String.from("")
    }

    mtd beginOperation(kind: OperationKind)
    {
        Debug.assert(.operation.kind == .None)
        .operation.kind       = kind
        .operation.error      = null
        .operation.job.lambda = &runMainWindowOperation
        .operation.job.data   = me
        .operation.timer      = .app().addTimer(50'ms, me)

        // Arming the tracker before the job starts is what clears the cancellation a previous
        // operation left behind.
        .operation.progress.begin(0)
        .showBusy(true)
        Jobs.schedule(&.operation.job)
    }

    mtd createContainer()
    {
        let path = .createPath.text()
        if !@countof(path)
        {
            .showError(appStrings().msg_ChooseCreateFile)
            return
        }

        if File.exists(path)
        {
            .showError(appStrings().msg_FileExists)
            return
        }

        if .createPassword.isEmpty()
        {
            .showError(appStrings().msg_PasswordRequired)
            return
        }

        if !Core.Crypto.constantTimeEqual(.createPassword.bytes(), .confirmPassword.bytes())
        {
            .showError(appStrings().msg_PasswordMismatch)
            return
        }

        let size = catch .containerSize() as sizeError
        if sizeError != null
        {
            .showError(appStrings().msg_CreateFailed, sizeError)
            return
        }

        .operation.path = path
        .operation.size = size
        .operation.password.add(.createPassword.bytes())
        .createPassword.clear()
        .confirmPassword.clear()
        .statusProgress = 0
        .setStatus(.Randomizing)
        .setState(.Creating)
        .beginOperation(.Create)
    }

    // Asks a running creation to stop.
    //
    // The worker gives up at its next chunk boundary and unwinds like any other failure, which
    // is what deletes the partial container. The button goes down immediately so a second press
    // cannot start anything while that is happening.
    mtd stopCreating()
    {
        if .state != .Creating do
            return
        .operation.progress.cancel()
        .createButton.enable(false)
        .setStatus(.StopRequested)
    }

    mtd mountContainer()
    {
        let path = .mountPath.text()
        if !@countof(path)
        {
            .showError(appStrings().msg_ChooseExisting)
            return
        }

        if .mountPassword.isEmpty()
        {
            .showError(appStrings().msg_PasswordRequired)
            return
        }

        let mountPoint = .selectedMountPoint()
        if mountPoint.isEmpty()
        {
            .showError(appStrings().msg_NoDriveLetter)
            return
        }

        .operation.path  = path
        .operation.mount = mountPoint
        .operation.password.add(.mountPassword.bytes())
        .mountPassword.clear()
        .setStatus(.StartingDriver)
        .setState(.Mounting)
        .beginOperation(.Mount)
    }

    mtd unmountContainer()
    {
        if .state != .Mounted do
            return
        .setStatus(.Unmounting)
        .setState(.Unmounting)
        .beginOperation(.Unmount)
    }

    mtd runOperation()
    {
        switch #complete .operation.kind
        {
        case .None:
            return

        case .Create:
            var volume = catch Volume.create(.operation.path.toString(), .operation.password.toSlice(), .operation.size, &.operation.progress) as createError
            .operation.error = createError
            if createError == null do
                volume.close()

        case .Mount:
            discard catch .mounted.open(.operation.path.toString(), .operation.password.toSlice(), .operation.mount.toString()) as mountError
            .operation.error = mountError

        case .Unmount:
            discard catch .mounted.close() as unmountError
            .operation.error = unmountError
        }

        Core.Crypto.secureClear(.operation.password.toSlice())
        .operation.password.clear()
    }

    // Refreshes the status line of the operation that is still running.
    //
    // Only creation knows how far along it is; the other operations wait on the driver, and the
    // spinner already says everything that can honestly be said about them.
    mtd reportProgress()
    {
        if .operation.kind != .Create do
            return
        if .operation.progress.isCanceled() do
            return
        .statusProgress = cast(s32) (.operation.progress.ratio() * 100)
        .setStatus(.Randomizing)
    }

    mtd finishOperation()
    {
        Jobs.wait(&.operation.job)
        if .operation.timer
        {
            .removeTimer(.operation.timer!)
            .operation.timer = null
        }

        .showBusy(false)

        switch #complete .operation.kind
        {
        case .None:
            return

        case .Create:
            if isCanceledError(.operation.error)
            {
                // A creation the user stopped is an outcome, not a failure, so it reports on
                // the status line and never opens a dialog.
                .setStatus(.CreateCanceled)
            }
            elif .operation.error != null
            {
                .showError(appStrings().msg_CreateFailed, .operation.error)
                .setStatus(.CreateStopped)
            }
            else
            {
                .setStatus(.Created)
                .mountPath.setText(.operation.path)
            }

            .setState(.Ready)

        case .Mount:
            if .operation.error != null
            {
                .showError(appStrings().msg_MountFailed, .operation.error)
                .setStatus(.MountStopped)
                .setState(.Ready)
            }
            else
            {
                .statusDrive = .operation.mount
                .setStatus(.Mounted)
                .setState(.Mounted)
            }

        case .Unmount:
            if .operation.error != null do
                .showError(appStrings().msg_UnmountSyncStopped, .operation.error)
            .setStatus(.Unmounted)
            .setState(.Ready)
        }

        .operation.kind  = .None
        .operation.error = null
        .operation.path.clear()
        .operation.mount.clear()
        .operation.size = 0
    }

    // Releases the pending operation and the mounted volume. Safe to call more than once.
    mtd shutdown()
    {
        if .shuttingDown do
            return
        .shuttingDown = true

        if .operation.timer
        {
            .removeTimer(.operation.timer!)
            .operation.timer = null
        }

        if .operation.kind != .None
        {
            // Randomizing a hundred-gigabyte container takes minutes. Asking it to stop before
            // waiting is what keeps closing the window immediate; the operation unwinds and
            // deletes the partial file on its way out.
            .operation.progress.cancel()
            Jobs.wait(&.operation.job)
            .operation.kind = .None
        }

        discard catch .mounted.close()
        Core.Crypto.secureClear(.operation.password.toSlice())
        .operation.password.clear()
        .createPassword.clear()
        .confirmPassword.clear()
        .mountPassword.clear()
        .operation.error = null
    }
}

impl IWnd for MainWindow
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .operation.timer
        {
            if Jobs.isDone(&.operation.job) do
                .finishOperation()
            else do
                .reportProgress()
        }

        .wnd.IWnd.onTimerEvent(evt)
    }

    mtd impl onStateEvent(evt: *StateEvent)
    {
        if evt.kind == .Init
        {
            // Runs before the surface is first displayed: restore the persisted window
            // placement, language and dialog state, then keep the window on a visible
            // screen area. The surface is built in English, and the restored language
            // reaches it through the notification the switch below emits.
            catch g_App.loadState()
            .applyLanguage()
            .surface?.constrainPositionToScreen(topLeft: true, margin: 10)
            evt.accepted = true
        }
    }

    mtd impl onSerializeStateEvent(evt: *SerializeStateEvent)
    {
        // The browse dialogs share this state, so they reopen on the folder that held
        // the last accepted container, with its recent locations.
        catch evt.serializer.serialize("MainWindow.fileDlgState", &me.fileDlgState)
        catch evt.serializer.serialize("MainWindow.language", &me.language)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        catch g_App.saveState()
        .shutdown()
        .wnd.IWnd.onDestroyEvent(evt)
    }
}
