using Core, Gui, Pixel

enum AppState
{
    Ready
    Creating
    Mounting
    Unmounting
    Resizing
    ChangingAccess
}

enum OperationKind
{
    None
    Create
    Mount
    Unmount
    Resize
    ChangeAccess
}

enum AccessChangeKind
{
    Password
    KeyFiles
}

// Emphasis of the status line, from what the latest step left behind.
enum StatusTone
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
enum StatusMessage
{
    Ready                    // Nothing has run yet, or the last operation finished cleanly.
    Randomizing              // The container is being filled with random bytes; `statusProgress` says how far.
    StopRequested            // The user asked the running operation to stop.
    HiddenCreateCanceled     // Hidden creation stopped; replacing an older hidden volume can damage it.
    CreateCanceled           // Creation stopped on request and left nothing behind.
    StartingDriver           // The portable filesystem driver is starting.
    Unmounting               // The drive is being synchronized and unmounted.
    CreateStopped            // Container creation stopped.
    Created                  // The container was created and is ready to mount.
    MountStopped             // Mounting stopped.
    Mounted                  // A drive is mounted; `statusDrive` names its letter.
    MountedProtected         // The outer drive refuses writes into its authenticated hidden region.
    MountedReadOnly          // A drive is mounted for reading alone; `statusDrive` names its letter.
    Unmounted                // The drive was unmounted safely.
    Resizing                 // Blocks are being moved or added; `statusProgress` says how far.
    Camouflaging             // The random physical tail is being refreshed.
    ResizeCanceled           // Resizing stopped on request and left the previous geometry.
    ResizeStopped            // Resizing stopped.
    Resized                  // The container has another capacity; `statusDrive` says how much it holds.
    Camouflaged              // The logical capacity stayed unchanged and the physical size changed.
    AutoUnmounted            // A configured security event closed every protected drive.
    AutoUnmountStopped       // The drives closed, but at least one final synchronization stopped.
    ChangingPassword         // The key slot is being rewritten.
    PasswordChanged          // The container now opens with the new password.
    PasswordRemoved          // The container now opens without a password.
    PasswordStopped          // The password change stopped.
    ChangingKeyFiles         // A verified key-slot rotation is in progress.
    KeyFilesChanged          // The container now opens with the selected key files.
    KeyFilesStopped          // The key-file change stopped.
}

// Rows of the "create a new vault" form, in the order `createNewVaultCard` adds them.
//
// The form owns the labels it creates, so re-labelling one after a language switch names
// its row. Keep these next to the builder: they are two halves of one decision.
enum CreateRow
{
    Path         // Container file to create.
    Capacity     // Fixed size and its unit.
    Password     // Password protecting the container, or empty for none.
    Confirm      // Same password, entered again.
    KeyFiles     // Ordered files combined with the password.
}

// Rows of the "open an existing vault" form, in the order `createOpenVaultCard` adds them.
enum MountRow
{
    Path             // Container file to open.
    Password         // Password unlocking the container, or empty when it has none.
    KeyFiles         // Ordered files combined with the password.
    Drive            // Drive letter the volume appears on.
    MountOptions     // Read-only mounting and optional hidden-volume protection.
}

// Rows of the automatic-unmount form, in the order `createOptionsCard` adds them.
enum OptionsRow
{
    Privacy
    SessionLock
    Suspend
    Idle
    IdleTimeout
}

// A Windows condition that can close protected drives without an explicit button press.
enum AutoUnmountCause
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
struct ContainerSize
{
    bytes: u64        // Requested capacity in bytes, meaningful when `error` is empty.
    error: String     // Why the field cannot be used, in the active language; empty when it can.
}

// A container the window mounts again the next time Swag Vault starts.
//
// `needsPassword` retains its serialized name for existing settings, but means that some access
// input is required: a password, key files, or both. An unprotected vault comes up on its own;
// only a protected one is worth asking about at startup.
struct StartupVault
{
    path:          String     // Container file to mount.
    drive:         String     // Stable backend destination identifier; the name preserves saved-state compatibility.
    needsPassword: bool       // Whether opening it needs transient access input; serialized name kept for compatibility.
    readOnly:      bool       // Whether it was mounted read only, which the next start repeats.
    protectHidden: bool       // Reauthenticate hidden access before a writable startup mount.
}

// Settings of the last mount that completed successfully.
//
// These are the three choices needed to prepare the open-vault form at the next start. A
// credential is deliberately absent: passwords and key-file paths live only in their controls
// and the operation that consumes them.
struct MountSettings
{
    path:     String     // Container file that was mounted.
    drive:    String     // Stable backend destination identifier; the name preserves saved-state compatibility.
    readOnly: bool       // Whether the mount was for reading alone.
}

// Long operation running outside the UI thread. Only one runs at a time, and the window
// polls `task` with `timer` until the result is ready to be reported.
struct VaultOperation
{
    task:           Swag.Task         // Runtime task running `kind`.
    kind:           OperationKind     // Work the task performs, or `None` while the window is idle.
    timer:          *Timer?           // Polls the task while it runs.
    error:          Swag.Error        // Owns a worker failure until the UI thread reports it.
    path:           String            // Container file the operation acts on.
    mount:          String            // Stable backend destination identifier requested by a mount operation.
    mountLabel:     String            // Host-facing destination name reported when the operation completes.
    size:           u64               // Container size requested by a create or a grow.
    outerReserve:   u64
    createHidden:   bool
    protectHidden:  bool
    hiddenAccess:   VaultAccess
    camouflageOnly: bool               // Whether resize only refreshes the random physical tail.
    access:         VaultAccess        // Current password and key files, owned and cleared by the operation.
    replacement:    VaultAccess        // Access installed by a password or key-file change.
    resultKeyFiles: Array'String       // Key-file selection published after a verified change.
    volume:         *MountedVault?     // Mount a mount operation produced, or the one an unmount closes.

    // What the result has to report but the wiped inputs no longer say.
    readOnly:          bool                 // Whether a mount operation exposes the drive read only.
    usedProtection:    bool                 // Whether the container was opened with a password or key file.
    leavesUnprotected: bool                 // Whether an access change leaves neither a password nor a key file.
    removesPassword:   bool                 // Whether a password change leaves its password field empty.
    accessChange:      AccessChangeKind     // Which control family the change and its result belong to.
    fromStartup:       bool                 // Whether the mount came from the startup list rather than from the card.
    securityEpoch:     u64                  // Security-event generation at which this mount started.
    securityStopped:   bool                 // Whether a security event interrupted this mount.

    progress: VolumeProgress     // What the job has done, and the way to ask it to stop.
}

// Owns the complete application state. The UI thread owns this object; long
// operations use `operation` and report their result back through the timer.
struct MainWindow
{
    using wnd: Wnd

    // Text and control of the header, kept so a language switch can say it again.

    late
    {
        subtitle:         *Label
        appearanceButton: *AppearanceButton
    }

    // Controls of the automatic-unmount page.

    late
    {
        privacyModeControl: *CheckButton
        unmountOnLock:      *CheckButton
        unmountOnSuspend:   *CheckButton
        unmountOnIdle:      *CheckButton
        idleTimeout:        *ComboBox
    }

    // Controls of the "create a new vault" card.

    late
    {
        createPath:      *EditBox
        createSize:      *EditBox
        createUnit:      *ComboBox
        createPassword:  *PasswordEdit
        confirmPassword: *PasswordEdit
        createKeyFiles:  *KeyFileField
        createButton:    *PushButton
        browseCreate:    *PushButton
    }

    // Controls of the "open an existing vault" card.

    late
    {
        mountPath:      *EditBox
        mountPassword:  *PasswordEdit
        mountKeyFiles:  *KeyFileField
        drive:          *ComboBox
        mountOptions:   *StackLayoutCtrl
        protectHidden:  *CheckButton
        hiddenButton:   *PushButton
        readOnly:       *CheckButton
        mountButton:    *PushButton
        passwordButton: *PushButton
        keyFilesButton: *PushButton
        resizeButton:   *PushButton
        browseMount:    *PushButton
    }

    // The single status line displayed above the footer, the glyph whose color reports its tone,
    // and the spinner that replaces the glyph while work runs. The text and the glyph are written
    // only through `setStatus`, the spinner only through `showBusy`.

    late
    {
        statusView: *Wnd
        status:     *Label
        statusIcon: *Label
        statusBusy: *Spinner
    }

    // The cards are pages of one tab strip rather than columns of one grid: a vault is created,
    // opened, watched, or governed by automatic-unmount policy, and only one task is active at a
    // time. Side by side they would cost the width of every page while leaving the others idle.
    late tabs: *Tab

    // The form cards, kept whole so a language switch can re-label their headings, and the band
    // that says which drives the window currently exposes.
    layoutReady: bool
    fittingSize: bool

    createCard:  VaultCard
    mountCard:   VaultCard
    optionsCard: VaultCard

    // Not `undefined`: the band owns the drive list, and an owning array has to be constructed
    // before the window can put anything in it.
    mountedDrives: MountedDrives

    fileDlgState: FileDlgState     // Session browse state; serialized only when privacy mode is off.
    privacyMode:  bool = true
    state:        AppState
    shuttingDown: bool
    operation:    VaultOperation

    // Containers to mount at the next start, and what is left of that list while the window
    // works through it. Only the first survives a run.
    startupVaults:   Array'StartupVault
    startupQueue:    Array'StartupVault
    startupTimer:    *Timer?
    securityTimer:   *Timer?
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
    // It holds [[Gui.ReferenceLanguage]] until the user picks something else: Swag Vault is an
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
func caughtMessage(err: any?)->String
{
    let s = appStrings()

    switch err
    {
    case Error as volumeError:
        logDiagnostic(volumeError.message)

        // The last three kinds name a shape the filesystem layer refuses, never a container a
        // reader chose, so a reader can only be told the container is damaged.
        switch #complete volumeError.kind
        {
        case .PasswordRequired:  return s.msg_PasswordRequired
        case .SizeTooSmall:      return minimumSizeMessage()
        case .PasswordOrDamaged: return s.msg_ErrPasswordOrDamaged
        case .Corrupted:         return s.msg_ErrDamaged
        case .NotFound:          return s.msg_ErrNotFound
        case .AlreadyExists:     return s.msg_ErrAlreadyExists
        case .AccessDenied:      return s.msg_ErrAccessDenied
        case .HiddenProtected:   return s.msg_HiddenProtected
        case .WriteProtected:    return s.msg_ErrReadOnly
        case .SparseContainer:   return s.msg_ErrSparse
        case .DiskFull:          return s.msg_ErrDiskFull
        case .Io:                return s.msg_ErrIo
        case .Canceled:          return s.msg_OperationStopped
        case .InvalidInput:      return s.msg_ErrInvalidRequest
        case .General:           return s.msg_SystemError
        case .NotDirectory, .IsDirectory, .DirectoryNotEmpty: return s.msg_ErrDamaged
        }

    case Swag.SystemError as systemError:
        logDiagnostic(systemError.message)
        return s.msg_SystemError
    }

    return s.msg_OperationStopped
}

// Says the smallest capacity a container can have, in whole mebibytes.
func minimumSizeMessage()->String
{
    const Mebibyte = 1024'u64 * 1024
    return Format.toString(appStrings().msg_SizeMinimum, (MinimumSize + Mebibyte - 1) / Mebibyte)
}

// Sends the English diagnostic of a failure to the debugger output.
//
// It is deliberately not shown: the reader gets the sentence for the kind, and this is the
// line whoever reads a report needs to tell two failures of the same kind apart.
private func logDiagnostic(message: string?)
{
    if not message do
        return

    // Built as one owned string: it carries its terminator, which is what the debugger
    // output expects, and a view over a longer buffer would not.
    Debugger.log(Format.toString("Swag Vault: %\n", message))
}

// Whether an operation stopped because the user asked it to, rather than because something
// about the container or the system stopped it.
func isCanceledError(err: any?)->bool
{
    switch err
    {
    case Error as volumeError: return volumeError.kind == .Canceled
    }

    return false
}

// Sets a control in the fixed-width theme family.
//
// A path, a capacity, a unit, and a drive letter are read by the system, not by a reader, so
// they are set like the compiler sets a name it knows and never look like prose.
func setMachineFont(wnd: *Wnd)
{
    let theme = wnd.theme()
    wnd.style.setFont(theme.createDefaultFontFs(theme.metrics.defaultFixedFontSize), .Regular)
}

// Says a container size the way the capacity fields take it back.
//
// Whole gibibytes when the size is one, mebibytes otherwise: every container Swag Vault creates or
// grows is a round number of either, and a readout with three decimals says nothing a reader
// can act on.
func capacityText(bytes: u64)->String
{
    const Mebibyte = 1024'u64 * 1024
    const Gibibyte = Mebibyte * 1024
    if bytes >= Gibibyte and not (bytes % Gibibyte) do
        return Format.toString("% GiB", bytes / Gibibyte)
    return Format.toString("% MiB", (bytes + Mebibyte - 1) / Mebibyte)
}

// Reads a capacity field and its unit, or says why the pair cannot be used.
//
// Only what the number itself makes impossible is judged here — an empty field, a value that
// no longer fits, a zero. What is too small or too small *for this container* belongs to the
// operation that asked, because the two do not refuse for the same reason.
func parseCapacity(text: string, unitIndex: u32)->ContainerSize
{
    var result: retval

    let parsed = catch StrConv.parseU64(text) as parseError
    if parseError != null or parsed.ovf or parsed.eat != text.count or not parsed.value
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

// What the change-password box asks for after the open card already states current access.
struct PasswordChangeFields
{
    replacement: *PasswordEdit     // Password it opens with from now on, or empty to remove it.
    confirm:     *PasswordEdit     // `replacement`, entered again.
}

// What the resize box asks for.
struct VaultResizeFields
{
    capacity:     *EditBox         // Capacity the vault should hold from now on.
    unit:         *ComboBox        // Unit `capacity` is written in; `parseCapacity` reads this order.
    keepCapacity: *CheckButton     // Whether only the physical camouflage is refreshed.
}

// Fills `dialog` with what a password change asks for, and returns its fields.
//
// Built apart from the gesture that opens the box so the shape of the form can be measured in
// every language without running a modal loop.
func buildPasswordChangeForm(dialog: *FormDlg)->PasswordChangeFields
{
    let texts = appStrings()
    let form  = dialog.form
    VaultForm.configure(form)

    let replacement = form.addPasswordField(texts.ui_NewPassword, placeholder: texts.ui_OptionalPassword, help: texts.ui_RemovePasswordHelp)
    let confirm     = form.addPasswordField(texts.ui_ConfirmPassword, placeholder: texts.ui_EnterAgain)

    VaultForm.finish(form)
    return {replacement, confirm}
}

// Fills `dialog` with the work-specific choices for resizing a vault, and returns its fields.
func buildVaultResizeForm(dialog: *FormDlg)->VaultResizeFields
{
    let texts = appStrings()
    let form  = dialog.form
    VaultForm.configure(form)

    with let capacity = form.addTextField(texts.ui_NewCapacity, "256", help: texts.ui_NewCapacityHelp)
    {
        .setUnsignedIntegerRange(1, 1024 * 1024)
        .selectAll()
        .enable(false)
        setMachineFont(capacity)
    }

    let unit = VaultForm.addCapacityUnit(form)
    unit.enable(false)

    with let keepCapacity = form.addOptionField(texts.ui_KeepCapacity, help: texts.ui_KeepCapacityHelp)
    {
        .setState(.Checked)
        .sigChanged += func|capacity, unit|(button)
        {
            let enabled = not button.isChecked()
            capacity.enable(enabled)
            unit.enable(enabled)
        }
    }

    VaultForm.finish(form)
    return {capacity, unit, keepCapacity}
}

// Builds the complete replacement key-file set from the current selection. The current files
// remain on the open card; the box contains only the list being changed.
func buildKeyFileChangeForm(dialog: *FormDlg, current: const [..] String)->*KeyFileField
{
    VaultForm.configure(dialog.form)
    let result = KeyFileField.create(dialog.form)
    result.setPaths(current)
    discard dialog.form.addField(appStrings().ui_KeyFiles, result, help: appStrings().ui_KeyFilesHelp)
    VaultForm.finish(dialog.form)
    return result
}

impl MainWindow
{
    // Keep a stable wrapping width; fitToContent measures the tallest translated panel.
    const WindowWidth = 720's32

    // Idle delays the automatic-unmount picker offers, in minutes, and the one it starts on.
    const IdleChoices      = [5'u32, 15, 30, 60]
    const IdleDefaultIndex = 1'u32

    // The page that opens a vault.
    const OpenTabIndex = 1'u32

    func create(parent: *Wnd)->*MainWindow
    {
        let result  = Wnd.create'MainWindow(parent, "vault.mainWindow")
        let surface = result.surface!
        surface.setView(result)
        surface.minSize        = {WindowWidth, 0}
        result.backgroundStyle = .View
        result.language        = ReferenceLanguage

        result.createAppearanceButton()

        // One accent rule across the top identifies every standard Swag application surface.
        Separator.create(result, .Top, .Accent)

        result.createHeader()
        result.createFooter()
        result.createTabs()
        result.watchFormState()
        result.applyLanguage()
        result.applyLayout()
        result.setState(.Ready)
        result.setStatus(.Ready)

        // The window opens on the first thing there is to fill in, so it can be driven from the
        // keyboard alone. Only the page on show is in the ring: the strip is what moves between
        // the three, and a hidden card holds no keyboard stop.
        result.setInitialFocus(result.initialStop())
        result.layoutReady = true
        result.fitToContent()
        return result
    }

    // Creates the caption's appearance action, which persists the palette and language it applies.
    mtd createAppearanceButton()
    {
        with .appearanceButton = AppearanceButton.create(.surface!, "vault.appearance")
        {
            .sigThemeChanged += func|window = me|(button)
            {
                window.themeIndex = cast(u32, button.appearanceTheme)
                catch g_App.saveState()
            }

            .sigLanguageChanged += func|window = me|(button)
            {
                window.language = button.language
                catch g_App.saveState()
            }

            .sigAboutRequested += func|window = me|(?)
            {
                window.showAbout()
            }
        }
    }

    // Creates the four pages: the three stops in a vault's lifecycle, then the policy that can
    // close a protected drive without an explicit button press.
    mtd createTabs()
    {
        with .tabs = Tab.create(me)
        {
            .dockStyle = .Center
            .margin    = {32, 16, 32, 16}
            .setForm(.Flat)
            .setPageTransitions(true)
            .addItem(appStrings().ui_CreateTab, view: me.createNewVaultCard(me.tabs))
            .addItem(appStrings().ui_OpenTab, view: me.createOpenVaultCard(me.tabs))
            .addItem(appStrings().ui_MountedTab, view: me.createMountedDrivesCard(me.tabs))
            .addItem(appStrings().ui_OptionsTab, view: me.createOptionsCard(me.tabs))
            .sigSelectionChanged += func|window = me|(?) { window.arrangeCards() }
        }
    }

    // Opens the standard About box, dated and versioned by the compilation of this executable.
    mtd showAbout()
    {
        const BuildDate = #run Time.DateTime.now()
        let version = Format.toString("%.%.%", #swcversion, #swcrevision, #swcbuildnum)

        with var about: ApplicationAboutDlgParams
        {
            .productName     = ProductName
            .version         = version
            .buildDate       = BuildDate
            .sourceUrl       = "https://github.com/swag-lang/swc/tree/master/bin/apps/modules/swagvault"
            .copyrightHolder = "Christophe Beaudet"
        }

        discard AboutDlg.createApplication(.surface!, about).doModal()
    }

    // The stop the window opens on: the first thing there is to fill in on the page that is up.
    //
    // The strip reads first, so it is what the keyboard would otherwise start on — and the first
    // key press would then change page instead of typing into the form the reader is looking at.
    mtd initialStop()->*Wnd?
    {
        switch .tabs.selectedIndex
        {
        case 0:  return .createPath
        case 1:  return .mountPath
        case 2:  return .mountedDrives.list
        default: return .unmountOnLock
        }
    }

    // The tab assigns its page rectangle after announcing the selection. Arrange from the
    // window down, then refresh forms whose translated text changed without resizing them.
    mtd arrangeCards()
    {
        .applyLayout()
        .createCard.endForm()
        .mountCard.endForm()
        .mountOptions.computeLayout()
        .optionsCard.endForm()
        .mountedDrives.card.endForm()
    }

    // Measures every panel at the actual page width; switching tabs never changes the height.
    mtd requiredClientHeight(width: f32)->f32
    {
        var height = 0'f32
        for child in .children
        {
            if not child.isLocallyVisible() do
                continue
            let margin = child.layoutMargin()
            let room   = Math.max(0, width - margin.x - margin.z)
            if child == .tabs
            {
                let inset     = .tabs.padding
                let pageWidth = Math.max(0, room - inset.x - inset.z)
                var tallest   = 0'f32
                for card in [&.createCard, &.mountCard, &.optionsCard, &.mountedDrives.card] do
                    tallest = Math.max(tallest, card.panel.itf.measureContent({pageWidth, 0}).y)
                height += .tabs.itf.measureContent({room, 0}).y + Math.ceil(tallest)
            }
            else
            {
                height += Math.ceil(child.measure({room, 0}).preferred.y)
            }

            height += margin.y + margin.w
        }

        return Math.ceil(height)
    }

    // The frame supplies its own inset. Include it once, round out, and keep the saved origin.
    mtd fitToContent()
    {
        if not .layoutReady or .fittingSize do
            return
        .fittingSize = true
        defer .fittingSize = false
        let surface = .surface!
        let frame   = surface.wnd.padding
        let shadow  = surface.shadowMargin() * 2
        let width   = surface.size().x - frame.x - frame.z - shadow
        let height  = .requiredClientHeight(width) + frame.y + frame.w + shadow
        var pos     = surface.position
        pos.height        = Math.ceil(Math.ceil(height) * surface.dpiScale)
        surface.minSize.y = pos.height / surface.dpiScale
        if Math.abs(surface.position.height - pos.height) >= 0.5 do
            surface.setPosition(pos)
        .arrangeCards()
    }

    // Brings one page of the strip up.
    //
    // Nothing else: selecting is what arranges the page, through the signal below. A caller that
    // arranged the card itself would be running a pass a mouse click does not, which is exactly
    // how a card clipped in the shipped window went on passing its own containment test.
    mtd showTab(index: u32) { .tabs.setSelectedIndex(index) }

    // Follows every field an action depends on, so no action is ever live on a form
    // that cannot answer for it.
    mtd watchFormState()
    {
        for edit in [.createPath, .createSize, .mountPath] do
            edit.sigTextChanged += func|window = me|(?) { window.refreshActions() }
        for edit in [.createPassword, .confirmPassword, .mountPassword] do
            edit.sigChanged += func|window = me|(?) { window.refreshActions() }
        .drive.sigChanged += func|window = me|(?, ?) { window.refreshActions() }
        .watchSubmit()
    }

    // Follows Enter in every field, so a card can be answered from the keyboard.
    //
    // Enter presses the action of the card the field belongs to, not one action for the whole
    // surface: this window carries two dominant actions, and the field being typed in is what says
    // which of the two was meant.
    mtd watchSubmit()
    {
        for edit in [.createPath, .createSize] do
            edit.sigSubmitted += func|window = me|(?) { window.submitCreate() }
        for edit in [.createPassword, .confirmPassword] do
            edit.sigSubmitted += func|window = me|(?) { window.submitCreate() }
        .mountPath.sigSubmitted     += func|window = me|(?) { window.submitMount() }
        .mountPassword.sigSubmitted += func|window = me|(?) { window.submitMount() }
    }

    // Creates the container when the create form holds everything it needs.
    //
    // A form that cannot answer stays silent instead of opening a box: the button is already down
    // for the same reason, so Enter says exactly what the button says.
    mtd submitCreate()
    {
        if .state != .Ready or not .canCreate() do
            return
        .createContainer()
    }

    // Mounts the drive when the open form holds everything it needs.
    mtd submitMount()
    {
        if .state != .Ready or not .canMount() do
            return
        .mountContainer()
    }

    // Creates the product name and the sentence under it.
    mtd createHeader()
    {
        // The header is as tall as the two rows it holds, so a wrapped explanation is not
        // cut off by a height calibrated on the shortest of the shipped languages.
        with let header = StackLayoutCtrl.create(me, .Top)
        {
            .dockStyle = .Top
            .margin    = {32, 20, 32, 0}
            .spacing   = 4
        }

        with let titleRow = Wnd.create'Wnd(header, {0, 0, 0, 44})
        {
            .dockStyle = .Top
        }

        let titleFont = .theme().createDefaultFont(34, .Bold)

        with let title = Label.create(titleRow, ProductName)
        {
            .dockStyle = .Center
            .setTextAlignment(.Left, .Center)
            .style.setFont(titleFont, .Regular)
        }

        // The row is as tall as the line box of the name. A hand-tuned height clips it, and by a
        // fraction of a pixel: enough to cut a descender, not enough to be noticed until the name
        // is set in another face.
        titleRow.resize(titleRow.position.width, Math.max(titleRow.position.height, titleFont.height))

        with .subtitle = Label.create(header, appStrings().ui_Subtitle, {}, null, .WordWrap | .SecondaryText | .AutoHeight)
        {
            .dockStyle = .Top
            .setTextAlignment(.Left, .Top)
        }

        titleRow.applyLayout()
        header.computeLayout()
    }

    // Creates the attribution row and, above it, the status line.
    mtd createFooter()
    {
        with let footerRow = Wnd.create'Wnd(&.wnd, {0, 0, 0, 24})
        {
            .dockStyle = .Bottom
            .margin    = {32, 0, 32, 12}
        }

        // The attribution keeps what it owes: the product, the holder, and where it comes from.
        // Expanding the acronym as well made the line the widest thing on the surface, and the
        // window is now one card wide.
        with let credit = Label.create(footerRow, "WinFsp — Copyright (C) Bill Zissimopoulos — github.com/winfsp/winfsp", {}, null, .SecondaryText)
        {
            .dockStyle = .Center
            .setTextAlignment(.Left, .Center)
        }

        footerRow.applyLayout()

        // The status line is raised off the ground by the same slight panel shape as the card. A
        // border around it would draw a third box on a surface that already reads without one.
        with .statusView = Wnd.create'Wnd(&.wnd, {0, 0, 0, 52})
        {
            .dockStyle       = .Bottom
            .margin          = {32, 0, 32, 12}
            .backgroundStyle = .Panel
            .padding         = {20, 8, 20, 8}
        }

        with .statusIcon = Label.create(.statusView, "", {0, 0, 24})
        {
            .dockStyle = .Left
            .margin.z  = 12
        }

        // The spinner takes the glyph's place rather than a slot of its own: it is the same
        // 24-pixel square, and a docked window that is hidden takes no room, so the status text
        // starts at the same column whether work is running or not.
        with .statusBusy = Spinner.create(.statusView, {0, 0, 24, 24})
        {
            .dockStyle = .Left
            .margin.z  = 12
            .hide()
        }

        with .status = Label.create(.statusView, "")
        {
            .dockStyle = .Center
            .setTextAlignment(.Left, .Center)
        }

        .statusView.applyLayout()
    }

    // Creates the page listing the drives this window exposes.
    mtd createMountedDrivesCard(parent: *Wnd)->*Wnd
    {
        with .mountedDrives = MountedDrives.create(parent)
        {
            .unmountButton.sigPressed += func|window = me|(?) { window.unmountSelectedDrive() }
            .list.sigSelectionChanged += func|window = me|(?) { window.refreshActions() }
            .sigDrivesChanged         += func|window = me|(?) { window.refreshActions() }
            .list.sigCheckedChanged   += func|window = me|(?) { window.applyStartupMarks() }
        }

        // The semantic column shares are resolved again every time the table receives a new
        // width, so the header covers the complete logical client area at every surface size.
        .mountedDrives.list.listView.hookOnEvent = func|window = me|(?, evt)
        {
            if evt is ResizeEvent do
                window.mountedDrives.layoutColumns()
            return false
        }

        return .mountedDrives.card.panel
    }

    // Creates the privacy and automatic-unmount page.
    mtd createOptionsCard(parent: *Wnd)->*Wnd
    {
        .optionsCard = VaultCard.create(parent, appStrings().ui_OptionsCardTitle, appStrings().ui_OptionsCardHelp)
        .optionsCard.actions.hide()

        let form = .optionsCard.form
        .privacyModeControl = form.addOptionField(appStrings().ui_PrivacyMode, help: appStrings().ui_PrivacyModeHelp)
        .unmountOnLock      = form.addOptionField(appStrings().ui_UnmountOnLock, help: appStrings().ui_UnmountOnLockHelp)
        .unmountOnSuspend   = form.addOptionField(appStrings().ui_UnmountOnSuspend, help: appStrings().ui_UnmountOnSuspendHelp)
        .unmountOnIdle      = form.addOptionField(appStrings().ui_UnmountOnIdle, help: appStrings().ui_UnmountOnIdleHelp)
        .idleTimeout        = form.addChoiceField(appStrings().ui_IdleTimeout)

        for minutes in IdleChoices do
            .idleTimeout.addItem(Format.toString(appStrings().ui_Minutes, minutes))

        .privacyModeControl.sigChanged += func|window = me|(?) { window.readPrivacyControl() }
        for check in [.unmountOnLock, .unmountOnSuspend, .unmountOnIdle] do
            check.sigChanged += func|window = me|(?) { window.readAutoUnmountControls() }
        .idleTimeout.sigChanged += func|window = me|(?, ?) { window.readAutoUnmountControls() }
        .applyPrivacyControl()
        .applyAutoUnmountControls()
        .optionsCard.endForm()
        return .optionsCard.panel
    }

    // Applies privacy without firing the control's save callback.
    mtd applyPrivacyControl()
    {
        .privacyModeControl.setState(.privacyMode ? .Checked : .Unchecked)
        .mountedDrives.setStartupEnabled(not .privacyMode)
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

    // Returns the idle delay the picker entry at `index` offers, in minutes.
    mtd idleMinutesAt(index: u32)->u32 => index < IdleChoices.count ? IdleChoices[index] : IdleChoices[IdleDefaultIndex]

    // Returns the entry of the idle picker that offers `minutes`, or the default one.
    mtd idleIndexFor(minutes: u32)->u32
    {
        for choice, index in IdleChoices where choice == minutes do
            return cast(u32, index)
        return IdleDefaultIndex
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
        .statusIcon.show(not busy)
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
        .themeIndex = Math.min(.themeIndex, cast(u32, AppearanceTheme.Dark))
        .appearanceButton.setAppearanceTheme(cast(AppearanceTheme, .themeIndex))
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

        var glyphColor, textColor: Color
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

        var glyph = .theme().icon(ThemeIcons.About, themeActionIconSize(.themeMetrics()))
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
             .MountedProtected,
             .Resizing,
             .Camouflaging,
             .ChangingPassword,
             .ChangingKeyFiles: return .Active

        case .CreateStopped, .MountStopped, .ResizeStopped, .PasswordStopped, .KeyFilesStopped, .AutoUnmountStopped: return .Stopped

        case .Ready,
             .CreateCanceled,
             .HiddenCreateCanceled,
             .Created,
             .Unmounted,
             .ResizeCanceled,
             .Resized,
             .Camouflaged,
             .AutoUnmounted,
             .PasswordChanged,
             .PasswordRemoved,
             .KeyFilesChanged: return .Idle
        }
    }

    // Returns the current status message in the active language.
    mtd statusText()->String
    {
        let texts = appStrings()
        switch #complete .statusMessage
        {
        case .Ready:                return String.from(texts.msg_Ready)
        case .Randomizing:          return Format.toString(texts.msg_Randomizing, .statusProgress)
        case .StopRequested:        return String.from(texts.msg_StopRequested)
        case .HiddenCreateCanceled: return String.from(texts.msg_HiddenCreateCanceled)
        case .CreateCanceled:       return String.from(texts.msg_CreateCanceled)
        case .StartingDriver:       return String.from(texts.msg_StartingDriver)
        case .Unmounting:           return String.from(texts.msg_Unmounting)
        case .CreateStopped:        return String.from(texts.msg_CreateStopped)
        case .Created:              return String.from(texts.msg_Created)
        case .MountStopped:         return String.from(texts.msg_MountStopped)
        case .Mounted:              return Format.toString(texts.msg_Mounted, .statusDrive)
        case .MountedProtected:     return Format.toString(texts.msg_MountedProtected, .statusDrive)
        case .MountedReadOnly:      return Format.toString(texts.msg_MountedReadOnly, .statusDrive)
        case .Unmounted:            return String.from(texts.msg_Unmounted)
        case .Resizing:             return Format.toString(texts.msg_Resizing, .statusProgress)
        case .Camouflaging:         return Format.toString(texts.msg_Camouflaging, .statusProgress)
        case .ResizeCanceled:       return String.from(texts.msg_ResizeCanceled)
        case .ResizeStopped:        return String.from(texts.msg_ResizeStopped)
        case .Resized:              return Format.toString(texts.msg_Resized, .statusDrive)
        case .Camouflaged:          return String.from(texts.msg_Camouflaged)
        case .AutoUnmounted:        return String.from(texts.msg_AutoUnmounted)
        case .AutoUnmountStopped:   return String.from(texts.msg_AutoUnmountStopped)
        case .ChangingPassword:     return String.from(texts.msg_ChangingPassword)
        case .PasswordChanged:      return String.from(texts.msg_PasswordChanged)
        case .PasswordRemoved:      return String.from(texts.msg_PasswordRemoved)
        case .PasswordStopped:      return String.from(texts.msg_PasswordStopped)
        case .ChangingKeyFiles:     return String.from(texts.msg_ChangingPassword)
        case .KeyFilesChanged:      return String.from(texts.msg_KeyFilesChanged)
        case .KeyFilesStopped:      return String.from(texts.msg_KeyFilesStopped)
        }
    }

    // Creates the page that makes a new container.
    mtd createNewVaultCard(parent: *Wnd)->*Wnd
    {
        .createCard = VaultCard.create(parent, appStrings().ui_CreateCardTitle, appStrings().ui_CreateCardHelp)
        let card     = &.createCard
        let form     = card.form
        let fileIcon = .theme().icon(.OpenFile, themeRowIconSize(.themeMetrics()))

        with .createPath = form.addTextField(appStrings().ui_ContainerFile, placeholder: "C:\\path\\private", icon: fileIcon)
        {
            .updateFlags(.AcceptFileDrop)
            setMachineFont(me.createPath)
        }

        with .browseCreate = form.addRowAction(appStrings().ui_Browse, fileIcon)
        {
            .sigPressed += func|window = me|(?) { window.chooseContainer(window.createPath, true) }
        }

        with .createSize = form.addTextField(appStrings().ui_FixedCapacity, "256")
        {
            .setUnsignedIntegerRange(1, 1024 * 1024)
            setMachineFont(me.createSize)
        }

        .createUnit = VaultForm.addCapacityUnit(form)

        // The password is optional, and the card explains that above rather than under the
        // field: it is a fact about what this card produces, not a note about one control.
        .createPassword  = form.addPasswordField(appStrings().ui_Password, placeholder: appStrings().ui_OptionalPassword)
        .confirmPassword = form.addPasswordField(appStrings().ui_ConfirmPassword, placeholder: appStrings().ui_EnterAgain)
        .createKeyFiles  = KeyFileField.create(form)
        discard form.addField(appStrings().ui_KeyFiles, .createKeyFiles, help: appStrings().ui_KeyFilesHelp)

        // Creation is long enough to be worth stopping, so its own button becomes the way out
        // of it. A second control would sit dead on the card the rest of the time, and the card
        // already has one dominant action.
        //
        // It carries no width for that very reason: the caption changes with the state and
        // with the language, so the layout pass reads it from the button rather than from a
        // number tuned on one wording.
        with .createButton = PushButton.create(card.actions, appStrings().ui_CreateVault, form: .Strong)
        {
            .setIcon(me.theme().icon(.SaveAs, themeActionIconSize(me.themeMetrics())))
            .sigPressed += func|window = me|(?)
            {
                if window.state == .Creating do
                    window.stopLongOperation()
                else do
                    window.createContainer()
            }
        }

        card.actions.computeLayout()
        card.endForm()
        return card.panel
    }

    // Creates the page that mounts, resizes, and re-keys an existing container.
    mtd createOpenVaultCard(parent: *Wnd)->*Wnd
    {
        .mountCard = VaultCard.create(parent, appStrings().ui_MountCardTitle, appStrings().ui_MountCardHelp)
        let card     = &.mountCard
        let form     = card.form
        let fileIcon = .theme().icon(.OpenFile, themeRowIconSize(.themeMetrics()))

        with .mountPath = form.addTextField(appStrings().ui_ContainerFile, placeholder: appStrings().ui_ExistingContainer, icon: fileIcon)
        {
            .updateFlags(.AcceptFileDrop)
            setMachineFont(me.mountPath)
        }

        with .browseMount = form.addRowAction(appStrings().ui_Browse, fileIcon)
        {
            .sigPressed += func|window = me|(?) { window.chooseContainer(window.mountPath, false) }
        }

        .mountPassword = form.addPasswordField(appStrings().ui_Password, placeholder: appStrings().ui_ContainerPassword)
        with .hiddenButton = form.addRowAction(appStrings().ui_CreateHidden)
        {
            .sigPressed += func|window = me|(?) { window.createHiddenContainer() }
        }

        .mountKeyFiles = KeyFileField.create(form, canGenerate: false)
        discard form.addField(appStrings().ui_KeyFiles, .mountKeyFiles, help: appStrings().ui_KeyFilesHelp)

        // The lifetime of the drive belongs to the letter that carries it, so it is said under
        // that field rather than as a loose paragraph at the bottom of the card.
        .drive = form.addChoiceField(appStrings().ui_DriveLetter, help: appStrings().ui_DriveHelp)
        setMachineFont(.drive)
        .fillDriveChoice()

        // Under the letter rather than beside the password: it says what the drive will be, not
        // how the container is opened, and a reader deciding on a letter is already there.
        with .mountOptions = StackLayoutCtrl.create(form, .Left)
        {
            .spacing = form.themeMetrics().dialog_BtnPadding * 3
        }

        discard form.addField("", .mountOptions)
        .readOnly            = CheckButton.create(.mountOptions, appStrings().ui_ReadOnly)
        .protectHidden       = CheckButton.create(.mountOptions, appStrings().ui_ProtectHidden)
        .readOnly.sigChanged += func|window = me|(button) { window.protectHidden.enable(not button.isChecked()) }

        // The action bar stacks from its right edge, so the dominant action is created first and
        // ends up under the reader's thumb, with the two secondary ones to its left.
        //
        // The remaining actions are secondary on purpose: mounting is what a reader comes to this
        // card for. Each box asks only for the value it changes; the current password and key files
        // are stated once in this form and consumed from here.
        with .mountButton = PushButton.create(card.actions, appStrings().ui_MountDrive, form: .Strong)
        {
            .setIcon(me.theme().icon(.Play, themeActionIconSize(me.themeMetrics())))
            .sigPressed += func|window = me|(?) { window.mountContainer() }
        }

        with .resizeButton = PushButton.create(card.actions, appStrings().ui_Resize)
        {
            .sigPressed += func|window = me|(?)
            {
                if window.state == .Resizing do
                    window.stopLongOperation()
                else do
                    window.resizeVault()
            }
        }

        with .passwordButton = PushButton.create(card.actions, appStrings().ui_ChangePassword)
        {
            .sigPressed += func|window = me|(?) { window.changeVaultPassword() }
        }

        with .keyFilesButton = PushButton.create(card.actions, appStrings().ui_ChangeKeyFiles)
        {
            .sigPressed += func|window = me|(?) { window.changeVaultKeyFiles() }
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

        if .drive.items.count and not .selectMountPoint(previous) do
            .drive.setSelectedIndex(0, notify: false)
    }

    // Selects `mountPoint` when that backend destination is still available.
    mtd selectMountPoint(mountPoint: string)->bool
    {
        for &destination, index in .mountDestinations where destination.id == mountPoint
        {
            .drive.setSelectedIndex(cast(u32, index), notify: false)
            return true
        }

        return false
    }

    // Restores the non-secret choices of the last successful mount into the form.
    mtd restoreMountSettings()
    {
        if not .mountSettings.path.isEmpty() do
            .mountPath.setText(.mountSettings.path)
        if not .mountSettings.drive.isEmpty() do
            discard .selectMountPoint(.mountSettings.drive)
        .readOnly.setState(.mountSettings.readOnly ? .Checked : .Unchecked)
    }

    // Opens an error box saying `message`, followed by the sentence for `err` when there is one.
    mtd showError(message: string, err: any? = null)
    {
        if err == null do
            MessageDlg.error(.surface!, message)
        else do
            MessageDlg.error(.surface!, Format.toString("%\n\n%", message, caughtMessage(err)))
    }

    // Whether the create form holds everything a container needs.
    //
    // Neither password is read here: an empty pair is a vault that opens without one, and a
    // mismatch is reported when the button is pressed, because a form that goes down as soon as
    // the two differ would go down on every keystroke of the second one.
    mtd canCreate()->bool => .createPath.text().count != 0 and .createSize.text().count != 0

    // Whether the open form holds everything a drive needs.
    //
    // The password is not read: a container that opens without one is answered by an empty
    // field, and a wrong password is reported by the container, not by the form.
    mtd canMount()->bool => .mountPath.text().count != 0 and not .selectedMountPoint().isEmpty()

    // Whether the open form names a container the two secondary actions can act on.
    mtd canModifyVault()->bool => .mountPath.text().count != 0

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
        .keyFilesButton.enable(.canModifyVault())
        .resizeButton.enable(.canModifyVault())
        .hiddenButton.enable(.canModifyVault())
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
        .createButton.setIcon(.theme().icon(creating ? .Stop : .SaveAs, themeActionIconSize(.themeMetrics())))

        .resizeButton.enable(resizing or (ready and .canModifyVault()))
        .resizeButton.setText(resizing ? appStrings().ui_StopResizing : appStrings().ui_Resize)

        // Disabling a form disables every field and trailing control it owns.
        .createCard.form.enable(ready)
        .mountCard.form.enable(ready)
        .mountButton.enable(ready and .canMount())
        .passwordButton.enable(ready and .canModifyVault())
        .keyFilesButton.enable(ready and .canModifyVault())
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

        for name, index in [texts.ui_CreateTab, texts.ui_OpenTab, texts.ui_MountedTab, texts.ui_OptionsTab] do
            .tabs.setItemName(cast(u32, index), name)

        .createCard.setTexts(texts.ui_CreateCardTitle, texts.ui_CreateCardHelp)
        .createCard.form.setRowLabel(cast(u64, CreateRow.Path), texts.ui_ContainerFile)
        .createCard.form.setRowLabel(cast(u64, CreateRow.Capacity), texts.ui_FixedCapacity)
        .createCard.form.setRowLabel(cast(u64, CreateRow.Password), texts.ui_Password)
        .createCard.form.setRowLabel(cast(u64, CreateRow.Confirm), texts.ui_ConfirmPassword)
        .createCard.form.setRowLabel(cast(u64, CreateRow.KeyFiles), texts.ui_KeyFiles)
        .createCard.form.setRowHelp(cast(u64, CreateRow.KeyFiles), texts.ui_KeyFilesHelp)
        .createPassword.setPlaceholder(texts.ui_OptionalPassword)
        .confirmPassword.setPlaceholder(texts.ui_EnterAgain)
        .createKeyFiles.retranslate()
        .browseCreate.setText(texts.ui_Browse)

        .mountCard.setTexts(texts.ui_MountCardTitle, texts.ui_MountCardHelp)
        .mountCard.form.setRowLabel(cast(u64, MountRow.Path), texts.ui_ContainerFile)
        .mountCard.form.setRowLabel(cast(u64, MountRow.Password), texts.ui_Password)
        .mountCard.form.setRowLabel(cast(u64, MountRow.KeyFiles), texts.ui_KeyFiles)
        .mountCard.form.setRowHelp(cast(u64, MountRow.KeyFiles), texts.ui_KeyFilesHelp)
        .mountCard.form.setRowLabel(cast(u64, MountRow.Drive), texts.ui_DriveLetter)
        .mountCard.form.setRowHelp(cast(u64, MountRow.Drive), texts.ui_DriveHelp)
        .readOnly.setText(texts.ui_ReadOnly)
        .protectHidden.setText(texts.ui_ProtectHidden)
        .hiddenButton.setText(texts.ui_CreateHidden)
        .mountPath.setPlaceholder(texts.ui_ExistingContainer)
        .mountPassword.setPlaceholder(texts.ui_ContainerPassword)
        .mountKeyFiles.retranslate()
        .browseMount.setText(texts.ui_Browse)
        .mountButton.setText(texts.ui_MountDrive)
        .passwordButton.setText(texts.ui_ChangePassword)
        .keyFilesButton.setText(texts.ui_ChangeKeyFiles)

        .optionsCard.setTexts(texts.ui_OptionsCardTitle, texts.ui_OptionsCardHelp)
        .optionsCard.form.setRowHelp(cast(u64, OptionsRow.Privacy), texts.ui_PrivacyModeHelp)
        .optionsCard.form.setRowHelp(cast(u64, OptionsRow.SessionLock), texts.ui_UnmountOnLockHelp)
        .optionsCard.form.setRowHelp(cast(u64, OptionsRow.Suspend), texts.ui_UnmountOnSuspendHelp)
        .optionsCard.form.setRowHelp(cast(u64, OptionsRow.Idle), texts.ui_UnmountOnIdleHelp)
        .optionsCard.form.setRowLabel(cast(u64, OptionsRow.IdleTimeout), texts.ui_IdleTimeout)
        .privacyModeControl.setText(texts.ui_PrivacyMode)
        .unmountOnLock.setText(texts.ui_UnmountOnLock)
        .unmountOnSuspend.setText(texts.ui_UnmountOnSuspend)
        .unmountOnIdle.setText(texts.ui_UnmountOnIdle)
        .idleTimeout.clear()
        for minutes in IdleChoices do
            .idleTimeout.addItem(Format.toString(texts.ui_Minutes, minutes))
        .applyPrivacyControl()
        .applyAutoUnmountControls()

        // The create and resize buttons say what they do *now*, so their captions are the
        // state's to write, not this method's: during a creation the first reads "stop".
        .setState(.state)
        .refreshStatus()

        .applyLayout()
        .createCard.endForm()
        .mountCard.endForm()
        .mountOptions.computeLayout()
        .optionsCard.endForm()
        .createCard.actions.computeLayout()
        .mountCard.actions.computeLayout()
        .mountedDrives.retranslate()
        .fitToContent()
        .invalidate()
    }

    // Lets the reader pick the container file `target` names, for creating it or for opening it.
    mtd chooseContainer(target: *EditBox, create: bool)
    {
        // Privacy controls persistence, not the convenience of returning to the last folder
        // during this run. Serialization below remains the only path from this state to disk.
        with var options: FileDlgOptions
        {
            .state             = &me.fileDlgState
            .mode              = create ? .CreateFile : .SelectFile
            .title             = create ? appStrings().dlg_TitleCreate : appStrings().dlg_TitleOpen
            .confirmButtonText = create ? appStrings().dlg_BtnCreate : appStrings().dlg_BtnOpen
            .initialName       = create ? "volume" : ""
            .shortcuts.add({Env.SpecialDirectory.Desktop, appStrings().ui_Desktop})
            .shortcuts.add({Env.SpecialDirectory.UserDocuments, "Documents"})
        }

        let dialog = FileDlg.create(.surface!, options)
        if dialog.doModal() == Dialog.BtnOk do
            target.setText(dialog.selectedPath())
    }

    // Returns the backend identifier of the destination the picker selects, or an empty string.
    mtd selectedMountPoint()->String
    {
        let index = .drive.selectedIndex
        return String.from(index < .mountDestinations.count ? .mountDestinations[index].id : "")
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
        if .shuttingDown or not .autoUnmountEnabled(cause) do
            return

        .securityEpoch += 1
        .startupQueue.clear()
        let interruptedMount = .operation.kind == .Mount and .operation.usedProtection

        // A protected mount already in flight belongs to the event too. Waiting here lets the
        // worker hand its handle back before the notification returns; `finishOperation` sees the
        // changed epoch and closes it instead of publishing a new drive after the lock or sleep.
        if interruptedMount
        {
            .operation.securityStopped = true
            .operation.task.wait()
            .finishOperation()
        }

        var synchronizationStopped = interruptedMount and .statusMessage == .AutoUnmountStopped
        var unmounted = false
        var index     = .mountedDrives.drives.count
        while index
        {
            index -= 1
            let entry = &.mountedDrives.drives[index]
            if not entry.needsPassword do
                continue
            unmounted = true

            let mounted = entry.volume
            entry.volume = null
            if mounted
            {
                discard catch mounted.close() as closeError
                if closeError != null do
                    synchronizationStopped = true
                Memory.delete(mounted)
            }

            .mountedDrives.drives.removeAtOrdered(index)
        }

        if not interruptedMount and not unmounted do
            return

        .mountedDrives.refresh()
        .fillDriveChoice()
        .setStatus(synchronizationStopped ? .AutoUnmountStopped : .AutoUnmounted)
    }

    mtd beginOperation(kind: OperationKind)
    {
        Swag.assert(.operation.kind == .None)
        .operation.kind = kind
        .operation.error.reset()
        .operation.timer = .addTimer(50'ms)

        // Arming the tracker before the task starts is what clears the cancellation a previous
        // operation left behind.
        .operation.progress.begin(0)
        .showBusy(true)

        .operation.task.submit(func|window = me|() { window.runOperation() })
    }

    mtd createContainer()
    {
        let path = .createPath.text()
        if path.count == 0
        {
            .showError(appStrings().msg_ChooseCreateFile)
            return
        }

        if File.exists(path)
        {
            .showError(appStrings().msg_FileExists)
            return
        }

        if not Core.Crypto.constantTimeEqual(.createPassword.bytes(), .confirmPassword.bytes())
        {
            .showError(appStrings().msg_PasswordMismatch)
            return
        }

        let size = parseCapacity(.createSize.text(), .createUnit.selectedIndex)
        if not size.error.isEmpty()
        {
            .showError(size.error)
            return
        }

        if size.bytes < MinimumSize
        {
            .showError(minimumSizeMessage())
            return
        }

        .operation.createHidden  = false
        .operation.protectHidden = false
        .operation.hiddenAccess.clear()
        .operation.path = path
        .operation.size = size.bytes
        .operation.access.setInputs(.createPassword.bytes(), .createKeyFiles.paths.toSlice())
        .createPassword.clear()
        .confirmPassword.clear()
        .statusProgress = 0
        .setStatus(.Randomizing)
        .setState(.Creating)
        .beginOperation(.Create)
    }

    // The open card identifies the outer container; this form owns only the new hidden access.
    mtd createHiddenContainer()
    {
        if not .canChangeVault() do
            return

        with var options: FormDlgOptions
        {
            .title = appStrings().ui_CreateHidden
            .confirmButtonText = appStrings().ui_CreateVault
            .width = 520
        }

        let dialog = FormDlg.create(.surface!, options)
        let fields = buildHiddenCreateForm(dialog)
        if dialog.doModal() != Dialog.BtnOk do
            return
        if not Core.Crypto.constantTimeEqual(fields.password.bytes(), fields.confirm.bytes())
        {
            .showError(appStrings().msg_PasswordMismatch)
            return
        }

        let size = parseCapacity(fields.capacity.text(), fields.unit.selectedIndex)
        if not size.error.isEmpty()
        {
            .showError(size.error)
            return
        }

        let reserve = parseCapacity(fields.reserve.text(), fields.reserveUnit.selectedIndex)
        if not reserve.error.isEmpty()
        {
            .showError(reserve.error)
            return
        }

        .operation.outerReserve = reserve.bytes
        .operation.hiddenAccess.setInputs(fields.password.bytes(), fields.keyFiles.paths.toSlice())
        if not .operation.hiddenAccess.isProtected()
        {
            .showError(appStrings().msg_PasswordRequired)
            return
        }

        .operation.path          = .mountPath.text()
        .operation.size          = size.bytes
        .operation.createHidden  = true
        .operation.protectHidden = false
        .operation.access.setInputs(.mountPassword.bytes(), .mountKeyFiles.paths.toSlice())
        .operation.resultKeyFiles = fields.keyFiles.paths
        .mountPassword.clear()
        .statusProgress = 0
        .setStatus(.Randomizing)
        .setState(.Creating)
        .showTab(0)
        .beginOperation(.Create)
    }

    // Asks for the access of the hidden volume the outer drive must not write over.
    mtd askHiddenProtection()->bool
    {
        with var options: FormDlgOptions
        {
            .title = appStrings().ui_ProtectHidden
            .confirmButtonText = appStrings().ui_MountDrive
            .width = 520
        }

        let dialog = FormDlg.create(.surface!, options)
        let fields = buildHiddenProtectionForm(dialog)
        if dialog.doModal() != Dialog.BtnOk do
            return false
        .operation.hiddenAccess.setInputs(fields.password.bytes(), fields.keyFiles.paths.toSlice())
        if not .operation.hiddenAccess.isProtected()
        {
            .showError(appStrings().msg_PasswordRequired)
            return false
        }

        return true
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
        if path.count == 0
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

        .operation.createHidden = false
        .operation.hiddenAccess.clear()
        .operation.protectHidden = .protectHidden.isChecked() and not .readOnly.isChecked()
        .protectHidden.setState(.Unchecked)
        if .operation.protectHidden and not .askHiddenProtection() do
            return
        .operation.access.setInputs(.mountPassword.bytes(), .mountKeyFiles.paths.toSlice())
        .mountPassword.clear()
        .startMount(String.from(path), mountPoint, false, .readOnly.isChecked())
    }

    // Starts the mount the password already staged in the operation opens.
    mtd startMount(path, mountPoint: String, fromStartup: bool, readOnly: bool)
    {
        .operation.path           = path
        .operation.mount          = mountPoint
        .operation.mountLabel     = .mountPointLabel(.operation.mount)
        .operation.fromStartup    = fromStartup
        .operation.readOnly       = readOnly
        .operation.usedProtection = .operation.access.isProtected() or .operation.protectHidden
        .operation.securityEpoch  = .securityEpoch
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

    // Whether the open card names a container that can be changed now, saying why when it cannot.
    //
    // A mounted container is in use by Windows: changing its geometry or its key slots under the
    // driver would corrupt what the drive is reading.
    mtd canChangeVault()->bool
    {
        if .state != .Ready or not .canModifyVault() do
            return false
        if .isMounted(.mountPath.text())
        {
            .showError(appStrings().msg_UnmountFirst)
            return false
        }

        return true
    }

    // Changes only the password. Current access and the retained key-file set come from the open
    // card, so the box contains the new password and its confirmation alone.
    mtd changeVaultPassword()
    {
        if not .canChangeVault() do
            return

        with var options: FormDlgOptions
        {
            .title  = appStrings().dlg_TitlePassword
            .confirmButtonText = appStrings().dlg_BtnApply
            .width  = 520
            .height = 300
        }

        let dialog = FormDlg.create(.surface!, options)
        let fields = buildPasswordChangeForm(dialog)
        if dialog.doModal() != Dialog.BtnOk do
            return

        if not Core.Crypto.constantTimeEqual(fields.replacement.bytes(), fields.confirm.bytes())
        {
            .showError(appStrings().msg_PasswordMismatch)
            return
        }

        .operation.path = .mountPath.text()
        .operation.access.setInputs(.mountPassword.bytes(), .mountKeyFiles.paths.toSlice())
        .operation.replacement.setInputs(fields.replacement.bytes(), .mountKeyFiles.paths.toSlice())
        .mountPassword.clear()
        .operation.accessChange      = .Password
        .operation.leavesUnprotected = not .operation.replacement.isProtected()
        .operation.removesPassword   = fields.replacement.isEmpty()
        .setStatus(.ChangingPassword)
        .setState(.ChangingAccess)
        .beginOperation(.ChangeAccess)
    }

    // Changes only the ordered key-file set. The box starts from the files already stated on the
    // open card, and current access is verified before the replacement slot is published.
    mtd changeVaultKeyFiles()
    {
        if not .canChangeVault() do
            return

        with var options: FormDlgOptions
        {
            .title = appStrings().dlg_TitleChangeKeyFiles
            .confirmButtonText = appStrings().dlg_BtnApply
        }

        let dialog = FormDlg.create(.surface!, options)
        let files  = buildKeyFileChangeForm(dialog, .mountKeyFiles.paths.toSlice())
        if dialog.doModal() != Dialog.BtnOk or files.samePaths(.mountKeyFiles.paths.toSlice()) do
            return

        .operation.path = .mountPath.text()
        .operation.access.setInputs(.mountPassword.bytes(), .mountKeyFiles.paths.toSlice())
        .operation.replacement.setInputs(.mountPassword.bytes(), files.paths.toSlice())
        files.copyPaths(&.operation.resultKeyFiles)
        .mountPassword.clear()
        .operation.accessChange      = .KeyFiles
        .operation.leavesUnprotected = not .operation.replacement.isProtected()
        .setStatus(.ChangingKeyFiles)
        .setState(.ChangingAccess)
        .beginOperation(.ChangeAccess)
    }

    // Asks only for another capacity, then resizes with the access stated on the open card.
    mtd resizeVault()
    {
        if not .canChangeVault() do
            return

        let path = .mountPath.text()
        if not File.exists(path)
        {
            .showError(appStrings().msg_ChooseExisting)
            return
        }

        with var options: FormDlgOptions
        {
            .title  = appStrings().dlg_TitleResize
            .confirmButtonText = appStrings().dlg_BtnApply
            .width  = 520
            .height = 240
        }

        let dialog = FormDlg.create(.surface!, options)
        let fields = buildVaultResizeForm(dialog)
        if dialog.doModal() != Dialog.BtnOk do
            return

        var requestedSize  = 0'u64
        let camouflageOnly = fields.keepCapacity.isChecked()
        if not camouflageOnly
        {
            let size = parseCapacity(fields.capacity.text(), fields.unit.selectedIndex)
            if not size.error.isEmpty()
            {
                .showError(size.error)
                return
            }

            requestedSize = size.bytes
        }

        .operation.path = path
        .operation.size = requestedSize
        .operation.camouflageOnly = camouflageOnly
        .operation.access.setInputs(.mountPassword.bytes(), .mountKeyFiles.paths.toSlice())
        .mountPassword.clear()
        .statusProgress = 0
        .setStatus(camouflageOnly ? .Camouflaging : .Resizing)
        .setState(.Resizing)
        .beginOperation(.Resize)
    }

    mtd runOperation()
    {
        defer .operation.hiddenAccess.clear()
        var hiddenCredential: VaultCredential
        if .operation.createHidden or .operation.protectHidden
        {
            hiddenCredential = catch .operation.hiddenAccess.derive() as hiddenError
            if hiddenError != null
            {
                .operation.error.capture(hiddenError)
                .operation.access.clear()
                return
            }
        }

        var current: VaultCredential
        if .operation.kind != .None and .operation.kind != .Unmount
        {
            current = catch .operation.access.derive() as accessError
            if accessError != null
            {
                .operation.error.capture(accessError)
                .operation.access.clear()
                .operation.replacement.clear()
                return
            }
        }

        switch #complete .operation.kind
        {
        case .None:
            return

        case .Create:
            if .operation.createHidden
            {
                var volume = catch Volume.createHidden(.operation.path, current.toSlice(), hiddenCredential.toSlice(), .operation.size, &.operation.progress, .operation.outerReserve) as createError
                .operation.error.capture(createError)
                if createError == null do
                    volume.close()
            }
            else
            {
                var volume = catch Volume.create(.operation.path, current.toSlice(), .operation.size, &.operation.progress) as createError
                .operation.error.capture(createError)
                if createError == null do
                    volume.close()
            }

        case .Mount:
            let mounted = Memory.new'MountedVault()
            discard catch mounted.open(.operation.path, current.toSlice(), .operation.mount, .operation.readOnly, hiddenCredential.toSlice()) as mountError
            .operation.error.capture(mountError)
            if mountError != null
            {
                Memory.delete(mounted)
                .operation.volume = null
            }
            else
            {
                .operation.volume = mounted
            }

        case .Unmount:
            let mounted = .operation.volume
            if mounted
            {
                discard catch mounted.close() as unmountError
                .operation.error.capture(unmountError)
                Memory.delete(mounted)
                .operation.volume = null
            }

        case .Resize:
            var volume = catch Volume.open(.operation.path, current.toSlice()) as openError
            .operation.error.capture(openError)
            if openError == null
            {
                if .operation.camouflageOnly
                {
                    discard catch volume.reapplyCamouflage(&.operation.progress) as resizeError
                    .operation.error.capture(resizeError)
                }
                else
                {
                    discard catch volume.resize(.operation.size, &.operation.progress) as resizeError
                    .operation.error.capture(resizeError)
                }

                volume.close()
            }

        case .ChangeAccess:
            var replacement = catch .operation.replacement.derive() as deriveError
            .operation.error.capture(deriveError)
            if deriveError != null do
                break

            var volume = catch Volume.open(.operation.path, current.toSlice()) as openError
            .operation.error.capture(openError)
            if openError == null
            {
                discard catch volume.changePassword(current.toSlice(), replacement.toSlice()) as changeError
                .operation.error.capture(changeError)
                volume.close()
            }
        }

        .operation.access.clear()
        .operation.replacement.clear()
        .operation.hiddenAccess.clear()
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
        .statusProgress = cast(s32, .operation.progress.ratio() * 100)
        .setStatus(.operation.kind == .Create ? StatusMessage.Randomizing : (.operation.camouflageOnly ? StatusMessage.Camouflaging : StatusMessage.Resizing))
    }

    mtd finishOperation()
    {
        .operation.task.wait()
        catch .operation.error.raise() as operationError
        .stopTimer(&.operation.timer)
        .showBusy(false)

        switch #complete .operation.kind
        {
        case .None:
            return

        case .Create:
            if isCanceledError(operationError)
            {
                // A creation the user stopped is an outcome, not a failure, so it reports on
                // the status line and never opens a dialog.
                .setStatus(.operation.createHidden ? .HiddenCreateCanceled : .CreateCanceled)
            }
            elif operationError != null
            {
                .showError(appStrings().msg_CreateFailed, operationError)
                .setStatus(.CreateStopped)
            }
            else
            {
                .setStatus(.Created)
                .mountPath.setText(.operation.path)
                if .operation.createHidden
                {
                    .mountKeyFiles.setPaths(.operation.resultKeyFiles.toSlice())
                    .protectHidden.setState(.Unchecked)
                    .showTab(1)
                }
                else
                {
                    .mountKeyFiles.setPaths(.createKeyFiles.paths.toSlice())
                }
            }

        case .Mount:
            if operationError != null
            {
                // A startup mount reports on the status line alone: a box per vault would meet
                // the reader with a stack of them before the window is even readable.
                if not .operation.fromStartup and not .operation.securityStopped do
                    .showError(appStrings().msg_MountFailed, operationError)
                .setStatus(.operation.securityStopped ? StatusMessage.AutoUnmounted : StatusMessage.MountStopped)
            }
            elif .operation.usedProtection and .operation.securityEpoch != .securityEpoch
            {
                let mounted = .operation.volume
                if mounted
                {
                    discard catch mounted.close() as closeError
                    if closeError != null do
                        .setStatus(.AutoUnmountStopped)
                    Memory.delete(mounted)
                    .operation.volume = null
                }

                if .statusMessage != .AutoUnmountStopped do
                    .setStatus(.AutoUnmounted)
            }
            else
            {
                .rememberMountedDrive()
                .statusDrive = .operation.mountLabel
                .setStatus(.operation.readOnly ? .MountedReadOnly : (.operation.protectHidden ? .MountedProtected : .Mounted))
            }

            .fillDriveChoice()

        case .Unmount:
            if operationError != null do
                .showError(appStrings().msg_UnmountSyncStopped, operationError)
            .setStatus(.Unmounted)
            .fillDriveChoice()

        case .Resize:
            if isCanceledError(operationError)
            {
                .setStatus(.ResizeCanceled)
            }
            elif operationError != null
            {
                .showError(appStrings().msg_ResizeFailed, operationError)
                .setStatus(.ResizeStopped)
            }
            elif .operation.camouflageOnly
            {
                .setStatus(.Camouflaged)
            }
            else
            {
                .statusDrive = capacityText(.operation.size)
                .setStatus(.Resized)
            }

        case .ChangeAccess:
            if operationError != null
            {
                let keyFiles = .operation.accessChange == .KeyFiles
                .showError(keyFiles ? appStrings().msg_KeyFilesFailed : appStrings().msg_PasswordFailed, operationError)
                .setStatus(keyFiles ? StatusMessage.KeyFilesStopped : StatusMessage.PasswordStopped)
            }
            else
            {
                .rememberAccessChange()
                if .operation.accessChange == .KeyFiles
                {
                    .mountKeyFiles.setPaths(.operation.resultKeyFiles.toSlice())
                    .setStatus(.KeyFilesChanged)
                }
                else
                {
                    .setStatus(.operation.removesPassword ? StatusMessage.PasswordRemoved : StatusMessage.PasswordChanged)
                }
            }
        }

        .setState(.Ready)
        .operation.kind = .None
        .operation.error.reset()
        .operation.volume            = null
        .operation.usedProtection    = false
        .operation.leavesUnprotected = false
        .operation.createHidden      = false
        .operation.protectHidden     = false
        .operation.removesPassword   = false
        .operation.accessChange      = .Password
        .operation.fromStartup       = false
        .operation.securityStopped   = false
        .operation.camouflageOnly    = false
        .operation.path.clear()
        .operation.mount.clear()
        .operation.mountLabel.clear()
        .operation.resultKeyFiles.clear()
        .operation.size = 0

        if .startupQueue.count do
            .pumpStartupQueue()
    }

    // Adds the drive the mount operation produced to the band.
    mtd rememberMountedDrive()
    {
        let known = .startupIndex(.operation.path)
        if not .privacyMode
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
            .needsPassword = me.operation.usedProtection
            .readOnly      = me.operation.readOnly
            .protectHidden = me.operation.protectHidden
            .atStartup     = not me.privacyMode and known != Swag.U64.Max
        }

        if .operation.volume
        {
            let space = .operation.volume.space()
            entry.totalBytes     = space.total
            entry.availableBytes = space.available
        }

        // The letter is remembered as the one actually used, so a startup vault comes back on
        // the drive it was last seen on rather than on the one it was first marked with.
        if not .privacyMode and known != Swag.U64.Max
        {
            .startupVaults[known].drive         = .operation.mount
            .startupVaults[known].protectHidden = .operation.protectHidden
            .startupVaults[known].readOnly      = .operation.readOnly
        }

        .mountedDrives.drives.add(#move entry)
        .mountedDrives.refresh()
        catch g_App.saveState()
    }

    // Keeps the startup list truthful after any change to what opens the vault.
    mtd rememberAccessChange()
    {
        if .privacyMode do
            return
        let index = .startupIndex(.operation.path)
        if index != Swag.U64.Max
        {
            .startupVaults[index].needsPassword = not .operation.leavesUnprotected
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
    // A drive that is unmounted keeps its mark: the list is what Swag Vault mounts at its next
    // start, not what it happens to be showing now.
    mtd applyStartupMarks()
    {
        if .privacyMode do
            return
        for &one, index in .mountedDrives.drives
        {
            let checked = .mountedDrives.list.isLineChecked(cast(u32, index))
            if checked == one.atStartup do
                continue
            one.atStartup = checked

            let known = .startupIndex(one.path)
            if not checked
            {
                if known != Swag.U64.Max do
                    .startupVaults.removeAtOrdered(known)
                continue
            }

            if known != Swag.U64.Max do
                .startupVaults.removeAtOrdered(known)
            .startupVaults.add({one.path, one.drive, one.needsPassword, one.readOnly, one.protectHidden})
        }

        catch g_App.saveState()
    }

    // Mounts the next container marked for startup, asking for its transient access when needed.
    //
    // One at a time: a mount is a job, and the operation that finishes is what calls this
    // again, so the drives come up in order instead of all at once on one worker.
    mtd pumpStartupQueue()
    {
        while .startupQueue.count
        {
            let entry = .startupQueue[0]
            .startupQueue.removeAtOrdered(0)

            if entry.drive.isEmpty() or not File.exists(entry.path) or .isMounted(entry.path) do
                continue

            .operation.access.clear()
            if entry.needsPassword and not .askStartupAccess(entry.path) do
                continue

            .operation.protectHidden = entry.protectHidden and not entry.readOnly
            .operation.hiddenAccess.clear()
            if .operation.protectHidden and not .askHiddenProtection()
            {
                .operation.access.clear()
                .operation.protectHidden = false
                continue
            }

            .startMount(entry.path, entry.drive, true, entry.readOnly)
            return
        }
    }

    // Asks for the password and key files of one protected startup container.
    //
    // Skipping is an answer: a vault whose access material is not at hand simply does not come up,
    // and the mark it carries is left alone for the next start.
    mtd askStartupAccess(path: string)->bool
    {
        let title = Format.toString(appStrings().dlg_TitleUnlock, Path.fileName(path) orelse path)

        with var options: FormDlgOptions
        {
            .title             = title
            .confirmButtonText = appStrings().ui_MountDrive
            .cancelButtonText  = appStrings().dlg_BtnSkip
            .width             = 520
            .height            = 250
        }

        let dialog = FormDlg.create(.surface!, options)
        VaultForm.configure(dialog.form)
        let password = dialog.form.addPasswordField(appStrings().ui_Password, placeholder: appStrings().ui_ContainerPassword, help: path)
        let keyFiles = KeyFileField.create(dialog.form)
        discard dialog.form.addField(appStrings().ui_KeyFiles, keyFiles, help: appStrings().ui_KeyFilesHelp)
        VaultForm.finish(dialog.form)
        if dialog.doModal() != Dialog.BtnOk do
            return false

        .operation.access.setInputs(password.bytes(), keyFiles.paths.toSlice())
        return true
    }

    // Releases the pending operation and every mounted volume. Safe to call more than once.
    mtd shutdown()
    {
        if .shuttingDown do
            return
        .shuttingDown = true

        .stopTimer(&.operation.timer)
        .stopTimer(&.startupTimer)
        .stopTimer(&.securityTimer)
        .securityMonitor.stop()

        if .operation.kind != .None
        {
            // Randomizing a hundred-gigabyte container takes minutes. Asking it to stop before
            // waiting is what keeps closing the window immediate; the operation unwinds and
            // deletes the partial file on its way out.
            .operation.progress.cancel()
            .operation.task.wait()
            .operation.kind = .None
        }

        // The mount an operation was still holding is closed too: a mount that never reached
        // the band is exactly as real to Windows as one that did.
        if .operation.volume
        {
            discard catch .operation.volume.close()
            Memory.delete(.operation.volume)
            .operation.volume = null
        }

        for &one in .mountedDrives.drives where one.volume
        {
            discard catch one.volume.close()
            Memory.delete(one.volume)
            one.volume = null
        }

        .mountedDrives.drives.clear()
        .operation.access.clear()
        .operation.replacement.clear()
        .operation.hiddenAccess.clear()
        .operation.resultKeyFiles.clear()
        .createPassword.clear()
        .confirmPassword.clear()
        .mountPassword.clear()
        .operation.error.reset()
    }
}

impl IWnd for MainWindow
{
    // Takes a container dropped anywhere on the window that no field claimed first.
    //
    // Dropping one file says "open this" regardless of its name: the container format, not a
    // filename extension, identifies a vault. The window brings up the page that mounts it, fills
    // its path and puts the keyboard on it, which leaves the reader one access entry away from a
    // drive. A drop that lands on a path field is that field's own business and never reaches here.
    mtd impl onDragDropEvent(evt: *DragDropEvent)
    {
        let path = evt.data.singleFile()
        if not path
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
            if .operation.task.isDone() do
                .finishOperation()
            else do
                .reportProgress()
        }
        elif evt.timer == .startupTimer
        {
            // One shot: the queue drains through the operations that finish, not through
            // this timer.
            .stopTimer(&.startupTimer)
            .pumpStartupQueue()
        }
        elif evt.timer == .securityTimer
        {
            if .autoUnmount.onIdle and autoUnmountIdleMilliseconds() >= cast(u64, .autoUnmount.idleMinutes) * 60 * 1000 do
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
            .securityTimer = .addTimer(1's)

            // The startup mounts wait for a surface a reader can see: the first one may need
            // access input, and a box on a window that is not up yet has nothing to sit on.
            if not .privacyMode do
                .startupQueue.add(.startupVaults.toSlice())
            if .startupQueue.count do
                .startupTimer = .addTimer(200'ms)

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
        if not .privacyMode
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
            .showTab(Math.min(selectedTab, cast(u32, .tabs.items.count) - 1))
        }
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        elif evt.kind == .ThemeChanged and .layoutReady do
            .fitToContent()
        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        catch g_App.saveState()
        .shutdown()
        .wnd.IWnd.onDestroyEvent(evt)
    }
}
