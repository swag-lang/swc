using Core, Gui, Pixel

internal enum AppState
{
    Ready
    Creating
    Mounting
    Unmounting
    Resizing
    ChangingPassword
}

internal enum OperationKind
{
    None
    Create
    Mount
    Unmount
    Resize
    ChangePassword
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
    Ready                  // Nothing has run yet, or the last operation finished cleanly.
    Randomizing            // The container is being filled with random bytes; `statusProgress` says how far.
    StopRequested          // The user asked the running operation to stop.
    CreateCanceled         // Creation stopped on request and left nothing behind.
    StartingDriver         // The portable filesystem driver is starting.
    Unmounting             // The drive is being synchronized and unmounted.
    CreateStopped          // Container creation stopped.
    Created                // The container was created and is ready to mount.
    MountStopped           // Mounting stopped.
    Mounted                // A drive is mounted; `statusDrive` names its letter.
    MountedReadOnly        // A drive is mounted for reading alone; `statusDrive` names its letter.
    Unmounted              // The drive was unmounted safely.
    Resizing               // Blocks are being moved or added; `statusProgress` says how far.
    Camouflaging           // The random physical tail is being refreshed.
    ResizeCanceled         // Resizing stopped on request and left the previous geometry.
    ResizeStopped          // Resizing stopped.
    Resized                // The container has another capacity; `statusDrive` says how much it holds.
    Camouflaged            // The logical capacity stayed unchanged and the physical size changed.
    AutoUnmounted          // A configured security event closed every protected drive.
    AutoUnmountStopped     // The drives closed, but at least one final synchronization stopped.
    ChangingPassword       // The key slot is being rewritten.
    PasswordChanged        // The container now opens with the new password.
    PasswordRemoved        // The container now opens without a password.
    PasswordStopped        // The password change stopped.
}

// Rows of the "create a new vault" form, in the order `createNewVaultCard` adds them.
//
// The form owns the labels it creates, so re-labelling one after a language switch names
// its row. Keep these next to the builder: they are two halves of one decision.
internal enum CreateRow
{
    Path         // Container file to create.
    Capacity     // Fixed size and its unit.
    Password     // Password protecting the container, or empty for none.
    Confirm      // Same password, entered again.
}

// Rows of the "open an existing vault" form, in the order `createOpenVaultCard` adds them.
internal enum MountRow
{
    Path         // Container file to open.
    Password     // Password unlocking the container, or empty when it has none.
    Drive        // Drive letter the volume appears on.
    ReadOnly     // Whether the drive opens for reading alone.
}

// Rows of the automatic-unmount form, in the order `createOptionsCard` adds them.
internal enum OptionsRow
{
    Privacy
    SessionLock
    Suspend
    Idle
    IdleTimeout
}

// A Windows condition that can close protected drives without an explicit button press.
internal enum AutoUnmountCause
{
    SessionLock
    Suspend
    Idle
}

// Persisted automatic-unmount policy. Closing the application is deliberately absent: WinFsp
// callbacks and their keys live in this process, so every mount necessarily ends with it.
struct AutoUnmountSettings
{
    onSessionLock: bool = true
    onSuspend:     bool = true
    onIdle:        bool
    idleMinutes:   u32  = 15
}

// What a capacity field holds, or why it cannot be used.
//
// The form judges itself, so the reason is already the sentence a reader sees rather than a
// kind the shell would have to translate.
internal struct ContainerSize
{
    bytes: u64        // Requested capacity in bytes, meaningful when `error` is empty.
    error: String     // Why the field cannot be used, in the active language; empty when it can.
}

// A container the window mounts again the next time sVaultDrive starts.
//
// `needsPassword` is what keeps the start quiet: a vault that opens without one comes up on its
// own, and only a protected vault is worth asking about. It says nothing the first Argon2
// attempt would not have said, and it saves that attempt — which costs one full derivation per
// key slot when it fails.
struct StartupVault
{
    path:          String     // Container file to mount.
    drive:         String     // Stable backend destination identifier; the name preserves saved-state compatibility.
    needsPassword: bool       // Whether opening it needs a password.
    readOnly:      bool       // Whether it was mounted read only, which the next start repeats.
}

// Settings of the last mount that completed successfully.
//
// These are the three choices needed to prepare the open-vault form at the next start. A
// credential is deliberately absent: a password lives only in its edit box and the operation
// that consumes it, both of which wipe their bytes when they are done.
struct MountSettings
{
    path:     String     // Container file that was mounted.
    drive:    String     // Stable backend destination identifier; the name preserves saved-state compatibility.
    readOnly: bool       // Whether the mount was for reading alone.
}

// Long operation running outside the UI thread. Only one runs at a time, and the window
// polls `job` with `timer` until the result is ready to be reported.
struct VaultOperation
{
    job:            Jobs.Job                // Worker scheduled for `kind`.
    kind:           OperationKind           // Work the job performs, or `None` while the window is idle.
    timer:          #null *Timer            // Polls the job while it runs.
    error:          #null any               // Failure captured by the job, or null when it succeeded.
    path:           String                  // Container file the operation acts on.
    mount:          String                  // Stable backend destination identifier requested by a mount operation.
    mountLabel:     String                  // Host-facing destination name reported when the operation completes.
    size:           u64                     // Container size requested by a create or a grow.
    camouflageOnly: bool                    // Whether resize only refreshes the random physical tail.
    password:       Array'u8                // Password copy owned by the operation and wiped when it ends.
    replacement:    Array'u8                // New password of a change, empty when the change removes it.
    volume:         #null *MountedVault     // Mount a mount operation produced, or the one an unmount closes.

    // What the result has to report but the wiped inputs no longer say.
    readOnly:        bool     // Whether a mount operation exposes the drive read only.
    usedPassword:    bool     // Whether the container was opened with a password.
    removesPassword: bool     // Whether a password change leaves the container without one.
    fromStartup:     bool     // Whether the mount came from the startup list rather than from the card.
    securityEpoch:   u64      // Security-event generation at which this mount started.
    securityStopped: bool     // Whether a security event interrupted this mount.

    progress: VolumeProgress     // What the job has done, and the way to ask it to stop.
}

// Owns the complete application state. The UI thread owns this object; long
// operations use `operation` and report their result back through the timer.
struct MainWindow
{
    using wnd: Wnd

    // Text and control of the header, kept so a language switch can say it again.
    #[Swag.Late]
    {
        subtitle:         *Label
        appearanceButton: *AppearanceButton
    }

    // Controls of the automatic-unmount page.
    #[Swag.Late]
    {
        privacyModeControl: *CheckButton
        unmountOnLock:      *CheckButton
        unmountOnSuspend:   *CheckButton
        unmountOnIdle:      *CheckButton
        idleTimeout:        *ComboBox
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

    // Controls of the "open an existing vault" card.
    #[Swag.Late]
    {
        mountPath:      *EditBox
        mountPassword:  *PasswordEdit
        drive:          *ComboBox
        readOnly:       *CheckButton
        mountButton:    *PushButton
        passwordButton: *PushButton
        resizeButton:   *PushButton
        browseMount:    *PushButton
    }

    // The single status line displayed above the footer, the glyph whose color reports its tone,
    // and the spinner that replaces the glyph while work runs. The text and the glyph are written
    // only through `setStatus`, the spinner only through `showBusy`.
    #[Swag.Late]
    {
        statusView: *Wnd
        status:     *Label
        statusIcon: *Label
        statusBusy: *Spinner
    }

    // The cards are pages of one tab strip rather than columns of one grid: a vault is created,
    // opened, watched, or governed by automatic-unmount policy, and only one task is active at a
    // time. Side by side they would cost the width of every page while leaving the others idle.
    #[Swag.Late]
    tabs: *Tab

    // The form cards, kept whole so a language switch can re-label their headings, and the band
    // that says which drives the window currently exposes.
    createCard:  VaultCard = undefined
    mountCard:   VaultCard = undefined
    optionsCard: VaultCard = undefined

    // Not `undefined`: the band owns the drive list, and an owning array has to be constructed
    // before the window can put anything in it.
    mountedDrives: MountedDrives

    fileDlgState: FileDlgState
    privacyMode:  bool = true
    state:        AppState
    shuttingDown: bool
    operation:    VaultOperation

    // Containers to mount at the next start, and what is left of that list while the window
    // works through it. Only the first survives a run.
    startupVaults:   Array'StartupVault
    startupQueue:    Array'StartupVault
    startupTimer:    #null *Timer
    securityTimer:   #null *Timer
    securityMonitor: AutoUnmountMonitor

    // Last successful choices restored into the open-vault form. Passwords are never settings.
    mountSettings:     MountSettings
    mountDestinations: Array'MountDestination
    autoUnmount:       AutoUnmountSettings
    securityEpoch:     u64

    // What the status line says, plus the two values its wording interpolates: the drive
    // letter of the mounted message and the percentage of the randomizing one.
    statusMessage:  StatusMessage
    statusDrive:    String
    statusProgress: s32

    // Language tag applied at start, or empty to follow the language of the account.
    //
    // It holds [[Gui.ReferenceLanguage]] until the user picks something else: sVaultDrive is an
    // English application that speaks other languages on request, not one that guesses.
    language:   String
    themeIndex: u32
}

// The sentence a reader sees for `err`, in the active language.
//
// The volume and filesystem layers report an [[ErrorKind]] and an English diagnostic; the
// kind is what the shell can say something about, and the diagnostic goes to the debugger
// output for whoever reads a report. A kind that means nothing to a reader — a metadata
// record declaring an implausible entry count — reads as the generic damaged-container
// wording, because the detail is for a report and not for someone trying to mount a drive.
// Returns an owned string, not a view: one kind formats its sentence, and a view into
// that temporary would dangle as soon as the statement building it ends. The constant
// sentences are copied out of the string table for the same contract.
internal func caughtMessage(err: #null any)->String
{
    let s = appStrings()

    switch err
    {
    case Error as volumeError:
        logDiagnostic(volumeError.message)
        switch #complete volumeError.kind
        {
        case .PasswordRequired:
            return s.msg_PasswordRequired

        case .SizeTooSmall:
            return Format.toString(s.msg_SizeMinimum, (MinimumSize + 1024 * 1024 - 1) / (1024 * 1024))

        case .PasswordOrDamaged:
            return s.msg_ErrPasswordOrDamaged

        case .Corrupted:
            return s.msg_ErrDamaged

        case .NotFound:
            return s.msg_ErrNotFound

        case .AlreadyExists:
            return s.msg_ErrAlreadyExists

        case .AccessDenied:
            return s.msg_ErrAccessDenied

        case .WriteProtected:
            return s.msg_ErrReadOnly

        case .SparseContainer:
            return s.msg_ErrSparse

        case .DiskFull:
            return s.msg_ErrDiskFull

        case .Io:
            return s.msg_ErrIo

        case .Canceled:
            return s.msg_OperationStopped

        case .InvalidInput:
            return s.msg_ErrInvalidRequest

        // Kinds a reader cannot act on: they name a shape the filesystem layer refuses,
        // never a container a reader chose.
        case .General,
             .NotDirectory,
             .IsDirectory,
             .DirectoryNotEmpty:
            return s.msg_ErrDamaged
        }

    case Swag.SystemError as systemError:
        logDiagnostic(systemError.message)
        return s.msg_SystemError
    }

    return s.msg_OperationStopped
}

// Sends the English diagnostic of a failure to the debugger output.
//
// It is deliberately not shown: the reader gets the sentence for the kind, and this is the
// line whoever reads a report needs to tell two failures of the same kind apart.
private func logDiagnostic(message: #null string)
{
    if !message do
        return

    // Built as one owned string: it carries its terminator, which is what the debugger
    // output expects, and a view over a longer buffer would not.
    let line = Format.toString("sVaultDrive: %\n", message!)
    Debugger.log(line.toString())
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

// Says a container size the way the capacity fields take it back.
//
// Whole gibibytes when the size is one, mebibytes otherwise: every container sVaultDrive creates or
// grows is a round number of either, and a readout with three decimals says nothing a reader
// can act on.
internal func capacityText(bytes: u64)->String
{
    const Mebibyte = 1024'u64 * 1024
    const Gibibyte = Mebibyte * 1024
    if bytes >= Gibibyte and !(bytes % Gibibyte) do
        return Format.toString("% GiB", bytes / Gibibyte)
    return Format.toString("% MiB", (bytes + Mebibyte - 1) / Mebibyte)
}

// Reads a capacity field and its unit, or says why the pair cannot be used.
//
// Only what the number itself makes impossible is judged here — an empty field, a value that
// no longer fits, a zero. What is too small or too small *for this container* belongs to the
// operation that asked, because the two do not refuse for the same reason.
internal func parseCapacity(text: string, unitIndex: u32)->ContainerSize
{
    var result: retval

    let parsed = catch StrConv.parseU64(text) as parseError
    if parseError != null or parsed.ovf or parsed.eat != @countof(text) or !parsed.value
    {
        result.error = appStrings().msg_SizeInvalid
        return result
    }

    let multiplier = unitIndex == 0 ? 1024'u64 * 1024 : 1024'u64 * 1024 * 1024
    if parsed.value > Swag.U64.Max / multiplier
    {
        result.error = appStrings().msg_SizeTooLarge
        return result
    }

    result.bytes = parsed.value * multiplier
    return result
}

// What the change-password box asks for.
//
// The password the container opens with today is asked for here rather than read off the open
// card. A credential typed to mount a drive is not permission to take the vault over, and a field
// left filled in would otherwise hand that permission to whoever reaches the keyboard next. The
// container refuses a wrong password either way; what the box adds is that nothing is changed
// until the reader has said it.
internal struct PasswordChangeFields
{
    current:     *PasswordEdit     // Password the vault opens with today.
    replacement: *PasswordEdit     // Password it opens with from now on, or empty to remove it.
    confirm:     *PasswordEdit     // `replacement`, entered again.
}

// What the resize box asks for.
internal struct VaultResizeFields
{
    current:      *PasswordEdit     // Password the vault opens with.
    capacity:     *EditBox          // Capacity the vault should hold from now on.
    unit:         *ComboBox         // Unit `capacity` is written in; `parseCapacity` reads this order.
    keepCapacity: *CheckButton      // Whether only the physical camouflage is refreshed.
}

// Fills `dialog` with what a password change asks for, and returns its fields.
//
// Built apart from the gesture that opens the box so the shape of the form can be measured in
// every language without running a modal loop.
internal func buildPasswordChangeForm(dialog: *FormDlg)->PasswordChangeFields
{
    let texts = appStrings()
    let form  = dialog.form

    let current     = form.addPasswordField(texts.ui_CurrentPassword, placeholder: texts.ui_ContainerPassword, help: texts.ui_CurrentPasswordHelp)
    let replacement = form.addPasswordField(texts.ui_NewPassword, placeholder: texts.ui_OptionalPassword, help: texts.ui_RemovePasswordHelp)
    let confirm     = form.addPasswordField(texts.ui_ConfirmPassword, placeholder: texts.ui_EnterAgain)

    form.computeLayout()
    return {current, replacement, confirm}
}

// Fills `dialog` with what resizing a vault of `currentSize` bytes asks for, and returns its fields.
//
// The password comes first here as it does in the box above: every box that changes a vault opens
// on the one question that has to be answered before any of the others matter.
internal func buildVaultResizeForm(dialog: *FormDlg)->VaultResizeFields
{
    let texts = appStrings()
    let form  = dialog.form

    let current = form.addPasswordField(texts.ui_CurrentPassword, placeholder: texts.ui_ContainerPassword, help: texts.ui_CurrentPasswordHelp)

    let capacity = form.addTextField(texts.ui_NewCapacity, "256", help: texts.ui_NewCapacityHelp)
    capacity.setUnsignedIntegerRange(1, 1024 * 1024)
    capacity.selectAll()
    setMachineFont(capacity)

    let unit = form.addRowChoice()
    unit.addItem("MiB")
    unit.addItem("GiB")
    unit.setSelectedIndex(0, notify: false)
    setMachineFont(unit)

    let keepCapacity = form.addOptionField(texts.ui_KeepCapacity, help: texts.ui_KeepCapacityHelp)
    keepCapacity.setState(.Checked)
    capacity.enable(false)
    unit.enable(false)
    keepCapacity.sigChanged += func|capacity, unit|(button)
    {
        let enabled = !button.isChecked()
        capacity.enable(enabled)
        unit.enable(enabled)
    }

    form.computeLayout()
    return {current, capacity, unit, keepCapacity}
}

impl MainWindow
{
    // Size one card needs, not three: the tab strip shows a single page at a time. The width is
    // the widest card's form plus its padding, and French wraps widest, so it is the language
    // that sizes this. The height is the tallest card, which is the one that opens a vault.
    const WindowWidth  = 720's32
    const WindowHeight = 930's32

    // The page that opens a vault.
    const OpenTabIndex = 1'u32

    func create(parent: *Wnd)->*MainWindow
    {
        let result  = Wnd.create'MainWindow(parent, "sVaultDrive.mainWindow")
        let surface = result.surface!
        surface.setView(result)
        surface.minSize        = {WindowWidth, WindowHeight}
        result.backgroundStyle = .View
        result.language        = ReferenceLanguage

        result.appearanceButton                 = AppearanceButton.create(surface, "sVaultDrive.appearance")
        result.appearanceButton.sigThemeChanged += func|window = result|(button)
        {
            window.themeIndex = button.appearanceTheme == .Light ? 1 : 0
            catch g_App.saveState()
        }
        result.appearanceButton.sigLanguageChanged += func|window = result|(button)
        {
            window.language = button.language
            catch g_App.saveState()
        }
        result.appearanceButton.sigAboutRequested += func|window = result|(button)
        {
            discard button
            window.showAbout()
        }

        // One accent rule across the top identifies every standard Swag application surface.
        Separator.create(result, .Top, .Accent)

        result.createHeader()
        result.createFooter()

        // Four pages: the three stops in a vault's lifecycle, then the policy that can close a
        // protected drive without an explicit button press.
        let tabs = Tab.create(result)
        result.tabs = tabs
        with tabs
        {
            .dockStyle = .Center
            .margin    = {32, 16, 32, 16}
            .setForm(.Flat)
            .setPageTransitions(true)
            .addItem(appStrings().ui_CreateTab, view: result.createNewVaultCard(tabs))
            .addItem(appStrings().ui_OpenTab, view: result.createOpenVaultCard(tabs))
            .addItem(appStrings().ui_MountedTab, view: result.createMountedDrivesCard(tabs))
            .addItem(appStrings().ui_OptionsTab, view: result.createOptionsCard(tabs))
        }

        tabs.sigSelectionChanged += func|window = result|(tab)
        {
            discard tab
            window.arrangeCards()
        }

        result.watchFormState()
        result.applyLanguage()
        result.applyLayout()
        result.setState(.Ready)
        result.setStatus(.Ready)

        // The window opens on the first thing there is to fill in, so it can be driven from the
        // keyboard alone. Only the page on show is in the ring: the strip is what moves between
        // the three, and a hidden card holds no keyboard stop.
        result.setInitialFocus(result.initialStop())
        return result
    }

    // Opens the standard product identity and provenance dialog.
    mtd showAbout()
    {
        const BuildDate = #run Time.DateTime.now()
        let version = Format.toString("%.%.%", #swcversion, #swcrevision, #swcbuildnum)
        let dlg     = AboutDlg.createApplication(.surface!, {
            productName: "sVaultDrive",
            version: version.toString(),
            buildDate: BuildDate,
            sourceUrl: "https://github.com/swag-lang/swc/tree/master/bin/apps/modules/sVaultDrive",
            copyrightHolder: "Christophe Beaudet"})
        discard dlg.doModal()
    }

    // The stop the window opens on: the first thing there is to fill in on the page that is up.
    //
    // The strip reads first, so it is what the keyboard would otherwise start on — and the first
    // key press would then change page instead of typing into the form the reader is looking at.
    mtd initialStop()->#null *Wnd
    {
        switch .tabs.selectedIndex
        {
        case 0:  return .createPath
        case 1:  return .mountPath
        case 2:  return .mountedDrives.list
        default: return .unmountOnLock
        }
    }

    // Finishes the card the strip has just brought up.
    //
    // A page is given its real width the moment it is shown, and that is the first width its card
    // has ever been measured at. A card is only correct after the pass that arranges its body
    // around a subtitle whose own height depends on that width — the same pass a language switch
    // needs, and for the same reason. Without it the body of a page opened for the first time is
    // short by that difference, and the body clips the last help paragraph of the form: the form
    // reports a height that ends inside a body which is not the body it was measured against.
    //
    // The layout is re-run from the window down, because the strip positions its page after it
    // announces the change, so the page still carries its old rectangle when this is called.
    mtd arrangeCards()
    {
        .applyLayout()
        .createCard.endForm()
        .mountCard.endForm()
        .optionsCard.endForm()
    }

    // Brings one page of the strip up.
    //
    // Nothing else: selecting is what arranges the page, through the signal below. A caller that
    // arranged the card itself would be running a pass a mouse click does not, which is exactly
    // how a card clipped in the shipped window went on passing its own containment test.
    mtd showTab(index: u32)
    {
        .tabs.setSelectedIndex(index)
    }

    // Follows every field an action depends on, so no action is ever live on a form
    // that cannot answer for it.
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

    // Mounts the drive when the open form holds everything it needs.
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

        let titleRow = Wnd.create'Wnd(header, {0, 0, 0, 44})
        titleRow.dockStyle = .Top

        let titleFont = .theme().createDefaultFont(34, .Bold)
        let title     = Label.create(titleRow, "sVaultDrive")
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
        let footerRow = Wnd.create'Wnd(&.wnd, {0, 0, 0, 24})
        footerRow.dockStyle = .Bottom
        footerRow.margin    = {32, 0, 32, 12}

        // The attribution keeps what it owes: the product, the holder, and where it comes from.
        // Expanding the acronym as well made the line the widest thing on the surface, and the
        // window is now one card wide.
        let credit = Label.create(footerRow, "WinFsp — Copyright (C) Bill Zissimopoulos — github.com/winfsp/winfsp", {}, null, .SecondaryText)
        credit.dockStyle = .Center
        credit.setTextAlignment(.Left, .Center)
        footerRow.applyLayout()

        // The status line is raised off the ground by the same slight panel shape as the card. A
        // border around it would draw a third box on a surface that already reads without one.
        .statusView                 = Wnd.create'Wnd(&.wnd, {0, 0, 0, 52})
        .statusView.dockStyle       = .Bottom
        .statusView.margin          = {32, 0, 32, 12}
        .statusView.backgroundStyle = .Panel
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

    mtd createMountedDrivesCard(parent: *Wnd)->*Wnd
    {
        .mountedDrives = MountedDrives.create(parent)

        // The semantic column shares are resolved again every time the table receives a new
        // width, so the header covers the complete logical client area at every surface size.
        .mountedDrives.list.listView.hookOnEvent = func|window = me|(wnd, evt)
        {
            discard wnd
            if evt is ResizeEvent do
                window.mountedDrives.layoutColumns()
            return false
        }

        .mountedDrives.unmountButton.sigPressed += func|window = me|(btn)
        {
            discard btn
            window.unmountSelectedDrive()
        }

        .mountedDrives.list.sigSelectionChanged += func|window = me|(list)
        {
            discard list
            window.refreshActions()
        }

        .mountedDrives.sigDrivesChanged += func|window = me|(drives)
        {
            discard drives
            window.refreshActions()
        }

        .mountedDrives.list.sigCheckedChanged += func|window = me|(list)
        {
            discard list
            window.applyStartupMarks()
        }

        return .mountedDrives.card.panel
    }

    mtd createOptionsCard(parent: *Wnd)->*Wnd
    {
        let card = VaultCard.create(parent, appStrings().ui_OptionsCardTitle, appStrings().ui_OptionsCardHelp)
        let form = card.form
        .optionsCard = card
        card.actions.hide()

        .privacyModeControl = form.addOptionField(appStrings().ui_PrivacyMode, help: appStrings().ui_PrivacyModeHelp)
        .unmountOnLock      = form.addOptionField(appStrings().ui_UnmountOnLock, help: appStrings().ui_UnmountOnLockHelp)
        .unmountOnSuspend   = form.addOptionField(appStrings().ui_UnmountOnSuspend, help: appStrings().ui_UnmountOnSuspendHelp)
        .unmountOnIdle      = form.addOptionField(appStrings().ui_UnmountOnIdle, help: appStrings().ui_UnmountOnIdleHelp)
        .idleTimeout        = form.addChoiceField(appStrings().ui_IdleTimeout)

        for minutes in [5'u32, 15, 30, 60] do
            .idleTimeout.addItem(Format.toString(appStrings().ui_Minutes, minutes).toString())

        .privacyModeControl.sigChanged += func|window = me|(button)
        {
            discard button
            window.readPrivacyControl()
        }
        .unmountOnLock.sigChanged += func|window = me|(button)
        {
            discard button
            window.readAutoUnmountControls()
        }
        .unmountOnSuspend.sigChanged += func|window = me|(button)
        {
            discard button
            window.readAutoUnmountControls()
        }
        .unmountOnIdle.sigChanged += func|window = me|(button)
        {
            discard button
            window.readAutoUnmountControls()
        }
        .idleTimeout.sigChanged += func|window = me|(combo, index)
        {
            discard combo
            discard index
            window.readAutoUnmountControls()
        }

        .applyPrivacyControl()
        .applyAutoUnmountControls()
        card.endForm()
        return card.panel
    }

    // Applies privacy without firing the control's save callback.
    mtd applyPrivacyControl()
    {
        .privacyModeControl.setState(.privacyMode ? .Checked : .Unchecked)
        .mountedDrives.setStartupEnabled(!.privacyMode)
    }

    // Removes every persisted or pending path while retaining appearance and
    // automatic-unmount preferences.
    mtd clearPrivateState()
    {
        .fileDlgState  = {}
        .mountSettings = {}
        .startupVaults.clear()
        .startupQueue.clear()
        for &one in .mountedDrives.drives do
            one.atStartup = false
        .mountedDrives.startupEnabled = false
        .mountedDrives.refresh()
        clearLegacyStateFiles()
    }

    mtd readPrivacyControl()
    {
        .privacyMode = .privacyModeControl.isChecked()
        if .privacyMode do
            .clearPrivateState()
        else do
            .mountedDrives.setStartupEnabled(true)
        catch g_App.saveState()
    }

    mtd idleMinutesAt(index: u32)->u32
    {
        switch index
        {
        case 0:  return 5
        case 2:  return 30
        case 3:  return 60
        default: return 15
        }
    }

    mtd idleIndexFor(minutes: u32)->u32
    {
        switch minutes
        {
        case 5:  return 0
        case 30: return 2
        case 60: return 3
        default: return 1
        }
    }

    // Applies persisted policy without firing the controls' save callbacks.
    mtd applyAutoUnmountControls()
    {
        .unmountOnLock.setState(.autoUnmount.onSessionLock ? .Checked : .Unchecked)
        .unmountOnSuspend.setState(.autoUnmount.onSuspend ? .Checked : .Unchecked)
        .unmountOnIdle.setState(.autoUnmount.onIdle ? .Checked : .Unchecked)
        .idleTimeout.setSelectedIndex(.idleIndexFor(.autoUnmount.idleMinutes), notify: false)
        .idleTimeout.enable(.autoUnmount.onIdle)
    }

    // Reads one complete policy snapshot and persists it immediately.
    mtd readAutoUnmountControls()
    {
        .autoUnmount.onSessionLock = .unmountOnLock.isChecked()
        .autoUnmount.onSuspend     = .unmountOnSuspend.isChecked()
        .autoUnmount.onIdle        = .unmountOnIdle.isChecked()
        .autoUnmount.idleMinutes   = .idleMinutesAt(.idleTimeout.selectedIndex)
        .idleTimeout.enable(.autoUnmount.onIdle)
        catch g_App.saveState()
    }

    // Puts the spinner in the glyph's place while an operation runs, and takes it back when the
    // operation ends. A spinner is the honest report for work whose remaining time is unknown;
    // creation and growth additionally write their percentage onto the status line.
    mtd showBusy(busy: bool)
    {
        if .statusBusy.isLocallyVisible() == busy do
            return
        .statusIcon.show(!busy)
        .statusBusy.show(busy)
        .statusView.applyLayout()
    }

    // Applies the persisted language, or the language of the account when none was picked.
    mtd applyLanguage()
    {
        discard catch .appearanceButton.setAppearanceLanguage(.language.toString())
    }

    // Applies the persisted standard application palette.
    mtd applyTheme()
    {
        .themeIndex = Math.min(.themeIndex, 1)
        .appearanceButton.setAppearanceTheme(.themeIndex ? .Light : .Dark)
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
        case .Randomizing,
             .StopRequested,
             .StartingDriver,
             .Unmounting,
             .Mounted,
             .MountedReadOnly,
             .Resizing,
             .Camouflaging,
             .ChangingPassword: return .Active

        case .CreateStopped, .MountStopped, .ResizeStopped, .PasswordStopped, .AutoUnmountStopped: return .Stopped

        case .Ready,
             .CreateCanceled,
             .Created,
             .Unmounted,
             .ResizeCanceled,
             .Resized,
             .Camouflaged,
             .AutoUnmounted,
             .PasswordChanged,
             .PasswordRemoved: return .Idle
        }
    }

    // Returns the current status message in the active language.
    mtd statusText()->String
    {
        let texts = appStrings()
        switch #complete .statusMessage
        {
        case .Ready:              return String.from(texts.msg_Ready)
        case .Randomizing:        return Format.toString(texts.msg_Randomizing, .statusProgress)
        case .StopRequested:      return String.from(texts.msg_StopRequested)
        case .CreateCanceled:     return String.from(texts.msg_CreateCanceled)
        case .StartingDriver:     return String.from(texts.msg_StartingDriver)
        case .Unmounting:         return String.from(texts.msg_Unmounting)
        case .CreateStopped:      return String.from(texts.msg_CreateStopped)
        case .Created:            return String.from(texts.msg_Created)
        case .MountStopped:       return String.from(texts.msg_MountStopped)
        case .Mounted:            return Format.toString(texts.msg_Mounted, .statusDrive)
        case .MountedReadOnly:    return Format.toString(texts.msg_MountedReadOnly, .statusDrive)
        case .Unmounted:          return String.from(texts.msg_Unmounted)
        case .Resizing:           return Format.toString(texts.msg_Resizing, .statusProgress)
        case .Camouflaging:       return Format.toString(texts.msg_Camouflaging, .statusProgress)
        case .ResizeCanceled:     return String.from(texts.msg_ResizeCanceled)
        case .ResizeStopped:      return String.from(texts.msg_ResizeStopped)
        case .Resized:            return Format.toString(texts.msg_Resized, .statusDrive)
        case .Camouflaged:        return String.from(texts.msg_Camouflaged)
        case .AutoUnmounted:      return String.from(texts.msg_AutoUnmounted)
        case .AutoUnmountStopped: return String.from(texts.msg_AutoUnmountStopped)
        case .ChangingPassword:   return String.from(texts.msg_ChangingPassword)
        case .PasswordChanged:    return String.from(texts.msg_PasswordChanged)
        case .PasswordRemoved:    return String.from(texts.msg_PasswordRemoved)
        case .PasswordStopped:    return String.from(texts.msg_PasswordStopped)
        }
    }

    mtd createNewVaultCard(parent: *Wnd)->*Wnd
    {
        let card = VaultCard.create(parent, appStrings().ui_CreateCardTitle, appStrings().ui_CreateCardHelp)
        let form = card.form
        .createCard = card

        .createPath = form.addTextField(appStrings().ui_ContainerFile, placeholder: "C:\\path\\private", icon: .theme().icon(ThemeIcons.OpenFile, 17))
        .createPath.updateFlags(.AcceptFileDrop)
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

        // The multiplier read by `parseCapacity` follows this order.
        .createUnit = form.addRowChoice()
        .createUnit.addItem("MiB")
        .createUnit.addItem("GiB")
        .createUnit.setSelectedIndex(0, notify: false)
        setMachineFont(.createUnit)

        // The password is optional, and the card explains that above rather than under the
        // field: it is a fact about what this card produces, not a note about one control.
        .createPassword  = form.addPasswordField(appStrings().ui_Password, placeholder: appStrings().ui_OptionalPassword)
        .confirmPassword = form.addPasswordField(appStrings().ui_ConfirmPassword, placeholder: appStrings().ui_EnterAgain)

        // Creation is long enough to be worth stopping, so its own button becomes the way out
        // of it. A second control would sit dead on the card the rest of the time, and the card
        // already has one dominant action.
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
                window.stopLongOperation()
            else do
                window.createContainer()
        }

        card.actions.computeLayout()
        card.endForm()
        return card.panel
    }

    mtd createOpenVaultCard(parent: *Wnd)->*Wnd
    {
        let card = VaultCard.create(parent, appStrings().ui_MountCardTitle, appStrings().ui_MountCardHelp)
        let form = card.form
        .mountCard = card

        .mountPath = form.addTextField(appStrings().ui_ContainerFile, placeholder: appStrings().ui_ExistingContainer, icon: .theme().icon(ThemeIcons.OpenFile, 17))
        .mountPath.updateFlags(.AcceptFileDrop)
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
        .fillDriveChoice()

        // Under the letter rather than beside the password: it says what the drive will be, not
        // how the container is opened, and a reader deciding on a letter is already there.
        .readOnly = form.addOptionField(appStrings().ui_ReadOnly, help: appStrings().ui_ReadOnlyHelp)

        // The action bar stacks from its right edge, so the dominant action is created first and
        // ends up under the reader's thumb, with the two secondary ones to its left.
        //
        // Those two are secondary on purpose: mounting is what a reader comes to this card for,
        // and changing the password or the capacity is what the same file happens to also allow.
        // Both name what they change rather than what they do, because both open a box that asks
        // for the rest — starting with the password the container opens with, which is never
        // taken from the field above.
        .mountButton = PushButton.create(card.actions, appStrings().ui_MountDrive, {0, 0, 0, 36}, form: .Strong)
        .mountButton.setIcon(.theme().icon(ThemeIcons.Play, 18))
        .mountButton.sigPressed += func|window = me|(btn)
        {
            discard btn
            window.mountContainer()
        }

        .resizeButton            = PushButton.create(card.actions, appStrings().ui_Resize, {0, 0, 0, 36})
        .resizeButton.sigPressed += func|window = me|(btn)
        {
            discard btn
            if window.state == .Resizing do
                window.stopLongOperation()
            else do
                window.resizeVault()
        }

        .passwordButton            = PushButton.create(card.actions, appStrings().ui_ChangePassword, {0, 0, 0, 36})
        .passwordButton.sigPressed += func|window = me|(btn)
        {
            discard btn
            window.changeVaultPassword()
        }

        card.actions.computeLayout()
        card.endForm()
        return card.panel
    }

    // Fills the picker with the destinations the active filesystem backend still has free.
    //
    // Mounting takes one and unmounting gives it back, so the list is said again after both:
    // a letter that is no longer free must not stay on offer.
    mtd fillDriveChoice()
    {
        let previous = .selectedMountPoint()
        .drive.clear()

        .mountDestinations = availableMountDestinations()
        for &destination in .mountDestinations do
            .drive.addItem(destination.label)

        if !.drive.items.count do
            return

        if .selectMountPoint(previous) do
            return

        .drive.setSelectedIndex(0, notify: false)
    }

    // Selects `mountPoint` when that backend destination is still available.
    mtd selectMountPoint(mountPoint: string)->bool
    {
        for &destination, index in .mountDestinations where destination.id == mountPoint
        {
            .drive.setSelectedIndex(cast(u32) index, notify: false)
            return true
        }

        return false
    }

    // Restores the non-secret choices of the last successful mount into the form.
    mtd restoreMountSettings()
    {
        if !.mountSettings.path.isEmpty() do
            .mountPath.setText(.mountSettings.path)
        if !.mountSettings.drive.isEmpty() do
            discard .selectMountPoint(.mountSettings.drive.toString())
        .readOnly.setState(.mountSettings.readOnly ? .Checked : .Unchecked)
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
    // Neither password is read here: an empty pair is a vault that opens without one, and a
    // mismatch is reported when the button is pressed, because a form that goes down as soon as
    // the two differ would go down on every keystroke of the second one.
    mtd canCreate()->bool
    {
        return @countof(.createPath.text()) != 0 and
               @countof(.createSize.text()) != 0
    }

    // Whether the open form holds everything a drive needs.
    //
    // The password is not read: a container that opens without one is answered by an empty
    // field, and a wrong password is reported by the container, not by the form.
    mtd canMount()->bool
    {
        return @countof(.mountPath.text()) != 0 and !.selectedMountPoint().isEmpty()
    }

    // Whether the open form names a container the two secondary actions can act on.
    mtd canModifyVault()->bool
    {
        return @countof(.mountPath.text()) != 0
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
        .passwordButton.enable(.canModifyVault())
        .resizeButton.enable(.canModifyVault())
        .mountedDrives.unmountButton.enable(.mountedDrives.selectedIndex() != Swag.U64.Max)
    }

    mtd setState(state: AppState)
    {
        .state = state
        let ready    = state == .Ready
        let creating = state == .Creating
        let resizing = state == .Resizing

        // The create and resize buttons stay live through their own long operation, because
        // during it they are what stops it. They are put in their new state before the forms go
        // down, so the keyboard a disabled form hands on lands on a control that still answers
        // rather than walking to the far end of the surface.
        .createButton.enable(creating or (ready and .canCreate()))
        .createButton.setText(creating ? appStrings().ui_StopCreating : appStrings().ui_CreateVault)
        .createButton.setIcon(.theme().icon(creating ? ThemeIcons.Stop : ThemeIcons.SaveAs, 18))

        .resizeButton.enable(resizing or (ready and .canModifyVault()))
        .resizeButton.setText(resizing ? appStrings().ui_StopResizing : appStrings().ui_Resize)

        // Disabling a form disables every field and trailing control it owns.
        .createCard.form.enable(ready)
        .mountCard.form.enable(ready)
        .mountButton.enable(ready and .canMount())
        .passwordButton.enable(ready and .canModifyVault())
        .mountedDrives.list.enable(ready)
        .mountedDrives.unmountButton.enable(ready and .mountedDrives.selectedIndex() != Swag.U64.Max)
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

        .subtitle.setText(texts.ui_Subtitle)

        .tabs.setItemName(0, texts.ui_CreateTab)
        .tabs.setItemName(1, texts.ui_OpenTab)
        .tabs.setItemName(2, texts.ui_MountedTab)
        .tabs.setItemName(3, texts.ui_OptionsTab)

        .createCard.setTexts(texts.ui_CreateCardTitle, texts.ui_CreateCardHelp)
        .createCard.form.setRowLabel(cast(u64) CreateRow.Path, texts.ui_ContainerFile)
        .createCard.form.setRowLabel(cast(u64) CreateRow.Capacity, texts.ui_FixedCapacity)
        .createCard.form.setRowLabel(cast(u64) CreateRow.Password, texts.ui_Password)
        .createCard.form.setRowLabel(cast(u64) CreateRow.Confirm, texts.ui_ConfirmPassword)
        .createPassword.setPlaceholder(texts.ui_OptionalPassword)
        .confirmPassword.setPlaceholder(texts.ui_EnterAgain)
        .browseCreate.setText(texts.ui_Browse)

        .mountCard.setTexts(texts.ui_MountCardTitle, texts.ui_MountCardHelp)
        .mountCard.form.setRowLabel(cast(u64) MountRow.Path, texts.ui_ContainerFile)
        .mountCard.form.setRowLabel(cast(u64) MountRow.Password, texts.ui_Password)
        .mountCard.form.setRowLabel(cast(u64) MountRow.Drive, texts.ui_DriveLetter)
        .mountCard.form.setRowHelp(cast(u64) MountRow.Drive, texts.ui_DriveHelp)
        .mountCard.form.setRowHelp(cast(u64) MountRow.ReadOnly, texts.ui_ReadOnlyHelp)
        .readOnly.setText(texts.ui_ReadOnly)
        .mountPath.setPlaceholder(texts.ui_ExistingContainer)
        .mountPassword.setPlaceholder(texts.ui_ContainerPassword)
        .browseMount.setText(texts.ui_Browse)
        .mountButton.setText(texts.ui_MountDrive)
        .passwordButton.setText(texts.ui_ChangePassword)

        .optionsCard.setTexts(texts.ui_OptionsCardTitle, texts.ui_OptionsCardHelp)
        .optionsCard.form.setRowHelp(cast(u64) OptionsRow.Privacy, texts.ui_PrivacyModeHelp)
        .optionsCard.form.setRowHelp(cast(u64) OptionsRow.SessionLock, texts.ui_UnmountOnLockHelp)
        .optionsCard.form.setRowHelp(cast(u64) OptionsRow.Suspend, texts.ui_UnmountOnSuspendHelp)
        .optionsCard.form.setRowHelp(cast(u64) OptionsRow.Idle, texts.ui_UnmountOnIdleHelp)
        .optionsCard.form.setRowLabel(cast(u64) OptionsRow.IdleTimeout, texts.ui_IdleTimeout)
        .privacyModeControl.setText(texts.ui_PrivacyMode)
        .unmountOnLock.setText(texts.ui_UnmountOnLock)
        .unmountOnSuspend.setText(texts.ui_UnmountOnSuspend)
        .unmountOnIdle.setText(texts.ui_UnmountOnIdle)
        .idleTimeout.clear()
        for minutes in [5'u32, 15, 30, 60] do
            .idleTimeout.addItem(Format.toString(texts.ui_Minutes, minutes).toString())
        .applyPrivacyControl()
        .applyAutoUnmountControls()

        // The create and resize buttons say what they do *now*, so their captions are the
        // state's to write, not this method's: during a creation the first reads "stop".
        .setState(.state)
        .refreshStatus()

        .applyLayout()
        .createCard.endForm()
        .mountCard.endForm()
        .optionsCard.endForm()
        .createCard.actions.computeLayout()
        .mountCard.actions.computeLayout()
        .mountedDrives.retranslate()
        .invalidate()
    }

    mtd chooseContainer(target: *EditBox, create: bool)
    {
        var options: FileDlgOptions
        options.state             = .privacyMode ? null : &.fileDlgState
        options.mode              = create ? .CreateFile : .SelectFile
        options.title             = create ? appStrings().dlg_TitleCreate : appStrings().dlg_TitleOpen
        options.confirmButtonText = create ? appStrings().dlg_BtnCreate : appStrings().dlg_BtnOpen
        options.initialName       = create ? "volume" : ""
        options.shortcuts.add({Env.SpecialDirectory.Desktop, appStrings().ui_Desktop})
        options.shortcuts.add({Env.SpecialDirectory.UserDocuments, "Documents"})

        let dialog = FileDlg.create(.surface!, options)
        if dialog.doModal() == Dialog.BtnOk do
            target.setText(dialog.selectedPath())
    }

    mtd selectedMountPoint()->String
    {
        let index = .drive.selectedIndex
        return index < .mountDestinations.count ? String.from(.mountDestinations[index].id) : String.from("")
    }

    // Returns the host-facing name for a backend destination identifier.
    mtd mountPointLabel(mountPoint: string)->String
    {
        for &destination in .mountDestinations where destination.id == mountPoint do
            return String.from(destination.label)
        return String.from(mountPoint)
    }

    // Whether a drive is already exposing this container.
    mtd isMounted(path: string)->bool
    {
        for &one in .mountedDrives.drives where one.path == path do
            return true
        return false
    }

    mtd autoUnmountEnabled(cause: AutoUnmountCause)->bool
    {
        switch #complete cause
        {
        case .SessionLock: return .autoUnmount.onSessionLock
        case .Suspend:     return .autoUnmount.onSuspend
        case .Idle:        return .autoUnmount.onIdle
        }
    }

    // Closes protected mounts synchronously. Lock and suspend notifications cannot leave cleanup
    // queued behind the event that is taking the session away.
    mtd handleAutoUnmount(cause: AutoUnmountCause)
    {
        if .shuttingDown or !.autoUnmountEnabled(cause) do
            return

        .securityEpoch += 1
        .startupQueue.clear()
        let interruptedMount = .operation.kind == .Mount and .operation.usedPassword

        // A protected mount already in flight belongs to the event too. Waiting here lets the
        // worker hand its handle back before the notification returns; `finishOperation` sees the
        // changed epoch and closes it instead of publishing a new drive after the lock or sleep.
        if interruptedMount
        {
            .operation.securityStopped = true
            Jobs.wait(&.operation.job)
            .finishOperation()
        }

        var synchronizationStopped = interruptedMount and .statusMessage == .AutoUnmountStopped
        var unmounted              = false
        var index                  = .mountedDrives.drives.count
        while index
        {
            index -= 1
            let entry = &.mountedDrives.drives[index]
            if !entry.needsPassword do
                continue
            unmounted = true

            let mounted = entry.volume
            entry.volume = null
            if mounted
            {
                discard catch mounted.close() as closeError
                if closeError != null do
                    synchronizationStopped = true
                Memory.delete(mounted!)
            }

            .mountedDrives.drives.removeAtOrdered(index)
        }

        if !interruptedMount and !unmounted do
            return

        .mountedDrives.refresh()
        .fillDriveChoice()
        .setStatus(synchronizationStopped ? .AutoUnmountStopped : .AutoUnmounted)
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

        if !Core.Crypto.constantTimeEqual(.createPassword.bytes(), .confirmPassword.bytes())
        {
            .showError(appStrings().msg_PasswordMismatch)
            return
        }

        let size = parseCapacity(.createSize.text(), .createUnit.selectedIndex)
        if !size.error.isEmpty()
        {
            .showError(size.error.toString())
            return
        }

        if size.bytes < MinimumSize
        {
            .showError(Format.toString(appStrings().msg_SizeMinimum, (MinimumSize + 1024 * 1024 - 1) / (1024 * 1024)).toString())
            return
        }

        .operation.path = path
        .operation.size = size.bytes
        .operation.password.add(.createPassword.bytes())
        .createPassword.clear()
        .confirmPassword.clear()
        .statusProgress = 0
        .setStatus(.Randomizing)
        .setState(.Creating)
        .beginOperation(.Create)
    }

    // Asks the running creation or growth to stop.
    //
    // The worker gives up at its next chunk boundary and unwinds like any other failure, which
    // is what deletes the partial container or puts a grown one back to its previous size. The
    // button goes down immediately so a second press cannot start anything while that happens.
    mtd stopLongOperation()
    {
        if .state != .Creating and .state != .Resizing do
            return
        .operation.progress.cancel()
        .createButton.enable(false)
        .resizeButton.enable(false)
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

        if .isMounted(path)
        {
            .showError(appStrings().msg_AlreadyMounted)
            return
        }

        let mountPoint = .selectedMountPoint()
        if mountPoint.isEmpty()
        {
            .showError(appStrings().msg_NoDriveLetter)
            return
        }

        .operation.password.add(.mountPassword.bytes())
        .mountPassword.clear()
        .startMount(String.from(path), mountPoint, false, .readOnly.state == .Checked)
    }

    // Starts the mount the password already staged in the operation opens.
    mtd startMount(path, mountPoint: String, fromStartup: bool, readOnly: bool)
    {
        .operation.path          = path
        .operation.mount         = mountPoint
        .operation.mountLabel    = .mountPointLabel(.operation.mount.toString())
        .operation.fromStartup   = fromStartup
        .operation.readOnly      = readOnly
        .operation.usedPassword  = .operation.password.count != 0
        .operation.securityEpoch = .securityEpoch
        .setStatus(.StartingDriver)
        .setState(.Mounting)
        .beginOperation(.Mount)
    }

    mtd unmountSelectedDrive()
    {
        if .state != .Ready do
            return
        let index = .mountedDrives.selectedIndex()
        if index == Swag.U64.Max do
            return

        .operation.path       = .mountedDrives.drives[index].path
        .operation.mount      = .mountedDrives.drives[index].drive
        .operation.mountLabel = .mountedDrives.drives[index].mountLabel
        .operation.volume     = .mountedDrives.detach(index)
        .setStatus(.Unmounting)
        .setState(.Unmounting)
        .beginOperation(.Unmount)
    }

    // Asks for the password the vault opens with today and the one it should open with from now
    // on, then rewrites the key slot.
    //
    // An empty new password removes the protection, which is the whole of "remove a password":
    // a container no password opens at all is unrecoverable and is never offered.
    mtd changeVaultPassword()
    {
        if .state != .Ready or !.canModifyVault() do
            return

        let path = String.from(.mountPath.text())
        if .isMounted(path.toString())
        {
            .showError(appStrings().msg_UnmountFirst)
            return
        }

        var options: FormDlgOptions
        options.title             = appStrings().dlg_TitlePassword
        options.confirmButtonText = appStrings().dlg_BtnApply
        options.width             = 520
        options.height            = 300

        let dialog = FormDlg.create(.surface!, options)
        let fields = buildPasswordChangeForm(dialog)
        if dialog.doModal() != Dialog.BtnOk do
            return

        if !Core.Crypto.constantTimeEqual(fields.replacement.bytes(), fields.confirm.bytes())
        {
            .showError(appStrings().msg_PasswordMismatch)
            return
        }

        .operation.path = path
        .operation.password.add(fields.current.bytes())
        .operation.replacement.add(fields.replacement.bytes())
        .operation.removesPassword = fields.replacement.isEmpty()
        .setStatus(.ChangingPassword)
        .setState(.ChangingPassword)
        .beginOperation(.ChangePassword)
    }

    // Asks for the password the vault opens with and another capacity, then resizes the container.
    mtd resizeVault()
    {
        if .state != .Ready or !.canModifyVault() do
            return

        let path = String.from(.mountPath.text())
        if .isMounted(path.toString())
        {
            .showError(appStrings().msg_UnmountFirst)
            return
        }

        if !File.exists(path.toString())
        {
            .showError(appStrings().msg_ChooseExisting)
            return
        }

        var options: FormDlgOptions
        options.title             = appStrings().dlg_TitleResize
        options.confirmButtonText = appStrings().dlg_BtnApply
        options.width             = 520
        options.height            = 240

        let dialog = FormDlg.create(.surface!, options)
        let fields = buildVaultResizeForm(dialog)
        if dialog.doModal() != Dialog.BtnOk do
            return

        var requestedSize  = 0'u64
        let camouflageOnly = fields.keepCapacity.isChecked()
        if !camouflageOnly
        {
            let size = parseCapacity(fields.capacity.text(), fields.unit.selectedIndex)
            if !size.error.isEmpty()
            {
                .showError(size.error.toString())
                return
            }

            requestedSize = size.bytes
        }

        .operation.path           = path
        .operation.size           = requestedSize
        .operation.camouflageOnly = camouflageOnly
        .operation.password.add(fields.current.bytes())
        .statusProgress = 0
        .setStatus(camouflageOnly ? .Camouflaging : .Resizing)
        .setState(.Resizing)
        .beginOperation(.Resize)
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
            let mounted = Memory.new'MountedVault()
            discard catch mounted.open(.operation.path.toString(), .operation.password.toSlice(), .operation.mount.toString(), .operation.readOnly) as mountError
            .operation.error = mountError
            if mountError != null
            {
                Memory.delete(mounted)
                .operation.volume = null
            }
            else do
                .operation.volume = mounted

        case .Unmount:
            let mounted = .operation.volume
            if mounted
            {
                discard catch mounted.close() as unmountError
                .operation.error = unmountError
                Memory.delete(mounted!)
                .operation.volume = null
            }

        case .Resize:
            var volume = catch Volume.open(.operation.path.toString(), .operation.password.toSlice()) as openError
            .operation.error = openError
            if openError == null
            {
                if .operation.camouflageOnly
                {
                    discard catch volume.reapplyCamouflage(&.operation.progress) as resizeError
                    .operation.error = resizeError
                }
                else
                {
                    discard catch volume.resize(.operation.size, &.operation.progress) as resizeError
                    .operation.error = resizeError
                }

                volume.close()
            }

        case .ChangePassword:
            var volume = catch Volume.open(.operation.path.toString(), .operation.password.toSlice()) as openError
            .operation.error = openError
            if openError == null
            {
                discard catch volume.changePassword(.operation.password.toSlice(), .operation.replacement.toSlice()) as changeError
                .operation.error = changeError
                volume.close()
            }
        }

        Core.Crypto.secureClear(.operation.password.toSlice())
        .operation.password.clear()
        Core.Crypto.secureClear(.operation.replacement.toSlice())
        .operation.replacement.clear()
    }

    // Refreshes the status line of the operation that is still running.
    //
    // Only the two operations that write bytes know how far along they are; the others wait on
    // the driver or on a key derivation, and the spinner already says everything that can
    // honestly be said about them.
    mtd reportProgress()
    {
        if .operation.kind != .Create and .operation.kind != .Resize do
            return
        if .operation.progress.isCanceled() do
            return
        .statusProgress = cast(s32) (.operation.progress.ratio() * 100)
        .setStatus(.operation.kind == .Create ? StatusMessage.Randomizing : (.operation.camouflageOnly ? StatusMessage.Camouflaging : StatusMessage.Resizing))
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

        case .Mount:
            if .operation.error != null
            {
                // A startup mount reports on the status line alone: a box per vault would meet
                // the reader with a stack of them before the window is even readable.
                if !.operation.fromStartup and !.operation.securityStopped do
                    .showError(appStrings().msg_MountFailed, .operation.error)
                .setStatus(.operation.securityStopped ? StatusMessage.AutoUnmounted : StatusMessage.MountStopped)
            }
            elif .operation.usedPassword and .operation.securityEpoch != .securityEpoch
            {
                let mounted = .operation.volume
                if mounted
                {
                    discard catch mounted.close() as closeError
                    if closeError != null do
                        .setStatus(.AutoUnmountStopped)
                    Memory.delete(mounted!)
                    .operation.volume = null
                }

                if .statusMessage != .AutoUnmountStopped do
                    .setStatus(.AutoUnmounted)
            }
            else
            {
                .rememberMountedDrive()
                .statusDrive = .operation.mountLabel
                .setStatus(.operation.readOnly ? .MountedReadOnly : .Mounted)
            }

            .fillDriveChoice()

        case .Unmount:
            if .operation.error != null do
                .showError(appStrings().msg_UnmountSyncStopped, .operation.error)
            .setStatus(.Unmounted)
            .fillDriveChoice()

        case .Resize:
            if isCanceledError(.operation.error)
            {
                .setStatus(.ResizeCanceled)
            }
            elif .operation.error != null
            {
                .showError(appStrings().msg_ResizeFailed, .operation.error)
                .setStatus(.ResizeStopped)
            }
            else
            {
                if .operation.camouflageOnly do
                    .setStatus(.Camouflaged)
                else
                {
                    .statusDrive = capacityText(.operation.size)
                    .setStatus(.Resized)
                }
            }

        case .ChangePassword:
            if .operation.error != null
            {
                .showError(appStrings().msg_PasswordFailed, .operation.error)
                .setStatus(.PasswordStopped)
            }
            else
            {
                .rememberPasswordChange()
                .setStatus(.operation.removesPassword ? StatusMessage.PasswordRemoved : StatusMessage.PasswordChanged)
            }
        }

        .setState(.Ready)
        .operation.kind            = .None
        .operation.error           = null
        .operation.volume          = null
        .operation.removesPassword = false
        .operation.fromStartup     = false
        .operation.securityStopped = false
        .operation.camouflageOnly  = false
        .operation.path.clear()
        .operation.mount.clear()
        .operation.mountLabel.clear()
        .operation.size = 0

        if .startupQueue.count do
            .pumpStartupQueue()
    }

    // Adds the drive the mount operation produced to the band.
    mtd rememberMountedDrive()
    {
        let known = .startupIndex(.operation.path.toString())

        if !.privacyMode
        {
            .mountSettings.path     = .operation.path
            .mountSettings.drive    = .operation.mount
            .mountSettings.readOnly = .operation.readOnly
        }

        with var entry: MountedDrive
        {
            .volume        = me.operation.volume
            .path          = me.operation.path
            .drive         = me.operation.mount
            .mountLabel    = me.operation.mountLabel
            .needsPassword = me.operation.usedPassword
            .readOnly      = me.operation.readOnly
            .atStartup     = !me.privacyMode and known != Swag.U64.Max
        }

        if .operation.volume
        {
            let space = .operation.volume!.space()
            entry.totalBytes     = space.total
            entry.availableBytes = space.available
        }

        // The letter is remembered as the one actually used, so a startup vault comes back on
        // the drive it was last seen on rather than on the one it was first marked with.
        if !.privacyMode and known != Swag.U64.Max
        {
            .startupVaults[known].drive    = .operation.mount
            .startupVaults[known].readOnly = .operation.readOnly
        }

        .mountedDrives.drives.add(#move entry)
        .mountedDrives.refresh()
        catch g_App.saveState()
    }

    // Keeps the startup list truthful after a password change.
    mtd rememberPasswordChange()
    {
        if .privacyMode do
            return
        let index = .startupIndex(.operation.path.toString())
        if index != Swag.U64.Max
        {
            .startupVaults[index].needsPassword = !.operation.removesPassword
            catch g_App.saveState()
        }
    }

    // Returns the startup entry for `path`, or `Swag.U64.Max` when there is none.
    mtd startupIndex(path: string)->u64
    {
        for &one, index in .startupVaults where one.path == path do
            return index
        return Swag.U64.Max
    }

    // Rebuilds the startup list from the check marks of the band.
    //
    // A drive that is unmounted keeps its mark: the list is what sVaultDrive mounts at its next
    // start, not what it happens to be showing now.
    mtd applyStartupMarks()
    {
        if .privacyMode do
            return
        for &one, index in .mountedDrives.drives
        {
            let checked = .mountedDrives.list.isLineChecked(cast(u32) index)
            if checked == one.atStartup do
                continue
            one.atStartup = checked

            let known = .startupIndex(one.path.toString())
            if !checked
            {
                if known != Swag.U64.Max do
                    .startupVaults.removeAtOrdered(known)
                continue
            }

            if known != Swag.U64.Max do
                .startupVaults.removeAtOrdered(known)
            .startupVaults.add({one.path, one.drive, one.needsPassword, one.readOnly})
        }

        catch g_App.saveState()
    }

    // Mounts the next container marked for startup, asking for its password when it has one.
    //
    // One at a time: a mount is a job, and the operation that finishes is what calls this
    // again, so the drives come up in order instead of all at once on one worker.
    mtd pumpStartupQueue()
    {
        while .startupQueue.count
        {
            let entry = .startupQueue[0]
            .startupQueue.removeAtOrdered(0)

            if entry.drive.isEmpty() or !File.exists(entry.path.toString()) or .isMounted(entry.path.toString()) do
                continue

            .operation.password.clear()
            if entry.needsPassword and !.askStartupPassword(entry.path.toString()) do
                continue

            .startMount(entry.path, entry.drive, true, entry.readOnly)
            return
        }
    }

    // Asks for the password of one startup container, and reports whether the reader gave one.
    //
    // Skipping is an answer: a vault whose password is not at hand simply does not come up,
    // and the mark it carries is left alone for the next start.
    mtd askStartupPassword(path: string)->bool
    {
        var options: FormDlgOptions
        options.title             = Format.toString(appStrings().dlg_TitleUnlock, Path.fileName(path) orelse path).toString()
        options.confirmButtonText = appStrings().ui_MountDrive
        options.cancelButtonText  = appStrings().dlg_BtnSkip
        options.width             = 520
        options.height            = 250

        let dialog   = FormDlg.create(.surface!, options)
        let password = dialog.form.addPasswordField(appStrings().ui_Password, placeholder: appStrings().ui_ContainerPassword, help: path)
        dialog.form.computeLayout()
        if dialog.doModal() != Dialog.BtnOk do
            return false

        .operation.password.add(password.bytes())
        return true
    }

    // Releases the pending operation and every mounted volume. Safe to call more than once.
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

        if .startupTimer
        {
            .removeTimer(.startupTimer!)
            .startupTimer = null
        }

        if .securityTimer
        {
            .removeTimer(.securityTimer!)
            .securityTimer = null
        }

        .securityMonitor.stop()

        if .operation.kind != .None
        {
            // Randomizing a hundred-gigabyte container takes minutes. Asking it to stop before
            // waiting is what keeps closing the window immediate; the operation unwinds and
            // deletes the partial file on its way out.
            .operation.progress.cancel()
            Jobs.wait(&.operation.job)
            .operation.kind = .None
        }

        // The mount an operation was still holding is closed too: a mount that never reached
        // the band is exactly as real to Windows as one that did.
        if .operation.volume
        {
            discard catch .operation.volume.close()
            Memory.delete(.operation.volume!)
            .operation.volume = null
        }

        for &one in .mountedDrives.drives where one.volume
        {
            discard catch one.volume.close()
            Memory.delete(one.volume!)
            one.volume = null
        }

        .mountedDrives.drives.clear()
        Core.Crypto.secureClear(.operation.password.toSlice())
        .operation.password.clear()
        Core.Crypto.secureClear(.operation.replacement.toSlice())
        .operation.replacement.clear()
        .createPassword.clear()
        .confirmPassword.clear()
        .mountPassword.clear()
        .operation.error = null
    }
}

impl IWnd for MainWindow
{
    // Takes a container dropped anywhere on the window that no field claimed first.
    //
    // Dropping one file says "open this" regardless of its name: the container format, not a
    // filename extension, identifies a vault. The window brings up the page that mounts it, fills
    // its path and puts the keyboard on it, which leaves the reader one password away from a
    // drive. A drop that lands on a path field is that field's own business and never reaches here.
    mtd impl onDragDropEvent(evt: *DragDropEvent)
    {
        let path = evt.data.singleFile()
        if !path
        {
            evt.accepted = false
            return
        }

        if evt.kind == .Drop
        {
            .showTab(OpenTabIndex)
            .mountPath.setText(path)
            .mountPath.setFocus()
        }

        evt.effect = pickDropEffect(evt.allowed & (DropEffect.Copy | DropEffect.Link), evt.modifiers)
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .operation.timer
        {
            if Jobs.isDone(&.operation.job) do
                .finishOperation()
            else do
                .reportProgress()
        }
        elif evt.timer == .startupTimer
        {
            // One shot: the queue drains through the operations that finish, not through
            // this timer.
            .removeTimer(.startupTimer!)
            .startupTimer = null
            .pumpStartupQueue()
        }
        elif evt.timer == .securityTimer
        {
            if .autoUnmount.onIdle and autoUnmountIdleMilliseconds() >= cast(u64) .autoUnmount.idleMinutes * 60 * 1000 do
                .handleAutoUnmount(.Idle)
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
            if .privacyMode
            {
                .clearPrivateState()
                catch g_App.saveState()
            }

            .applyTheme()
            .applyLanguage()
            .surface?.constrainPositionToScreen(topLeft: true, margin: 10)

            .securityMonitor.start(me)
            .securityTimer = .app().addTimer(1's, me)

            // The startup mounts wait for a surface a reader can see: the first one may need a
            // password, and a box on a window that is not up yet has nothing to sit on.
            if !.privacyMode do
                .startupQueue.add(.startupVaults.toSlice())
            if .startupQueue.count do
                .startupTimer = .app().addTimer(200'ms, me)

            evt.accepted = true
        }
    }

    mtd impl onSerializeStateEvent(evt: *SerializeStateEvent)
    {
        catch evt.serializer.serialize("MainWindow.privacyMode", &me.privacyMode)
        catch evt.serializer.serialize("MainWindow.language", &me.language)
        catch evt.serializer.serialize("MainWindow.themeIndex", &me.themeIndex)

        // Privacy is the default, including for state written before this setting
        // existed. Only an explicit opt-out permits paths or browse history on disk.
        if !.privacyMode
        {
            catch evt.serializer.serialize("MainWindow.fileDlgState", &me.fileDlgState)
            catch evt.serializer.serialize("MainWindow.mountSettings", &me.mountSettings)
            catch evt.serializer.serialize("MainWindow.startupVaults", &me.startupVaults)
        }

        catch evt.serializer.serialize("MainWindow.autoUnmount", &me.autoUnmount)

        // The window reopens on the page it was left on, so a reader who only ever mounts an
        // existing vault does not walk past the creation form at every start.
        var selectedTab = .tabs.selectedIndex
        catch evt.serializer.serialize("MainWindow.selectedTab", &selectedTab)
        if evt.serializer.isReading()
        {
            if .privacyMode do
                .clearPrivateState()
            else do
                .restoreMountSettings()
            .applyPrivacyControl()
            .applyAutoUnmountControls()
            .showTab(Math.min(selectedTab, cast(u32) .tabs.items.count - 1))
        }
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
