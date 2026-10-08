using Core, Gui, Pixel

// The long operation the window runs on its worker; `None` while the window waits for the reader.
enum OperationKind
{
    None
    Create
    Mount
    Unmount
    Resize
    ChangeAccess
}

// What an access change replaces: the password, or the set of key files.
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
    task:           Swag.Task          // Runtime task running `kind`.
    kind:           OperationKind      // Work the task performs, or `None` while the window is idle.
    timer:          *Timer?            // Polls the task while it runs.
    error:          Swag.Error         // Owns a worker failure until the UI thread reports it.
    path:           String             // Container file the operation acts on.
    mount:          String             // Stable backend destination identifier requested by a mount operation.
    mountLabel:     String             // Host-facing destination name reported when the operation completes.
    size:           u64                // Container size requested by a create or a grow.
    outerReserve:   u64                // Room the outer volume keeps for ordinary files when a hidden one is created.
    createHidden:   bool               // Whether a create operation makes a hidden volume inside an existing container.
    protectHidden:  bool               // Whether a mount refuses outer writes into the hidden region.
    hiddenAccess:   VaultAccess        // Hidden-volume password and key files, owned and cleared by the operation.
    camouflageOnly: bool               // Whether resize only refreshes the random physical tail.
    access:         VaultAccess        // Current password and key files, owned and cleared by the operation.
    replacement:    VaultAccess        // Access installed by a password or key-file change.
    resultKeyFiles: Array'String       // Key-file selection published after a verified change.
    volume:         *MountedVault?     // Mount a mount operation produced, or the one an unmount closes.

    // What the result has to report but the wiped inputs no longer say.
    readOnly:          bool     // Whether a mount operation exposes the drive read only.
    usedProtection:    bool     // Whether the container was opened with a password or key file.
    leavesUnprotected: bool     // Whether an access change leaves neither a password nor a key file.
    removesPassword:   bool     // Whether a password change leaves its password field empty.
    accessChange:      AccessChangeKind     // Which control family the change and its result belong to.
    fromStartup:       bool     // Whether the mount came from the startup list rather than from the card.
    securityEpoch:     u64      // Security-event generation at which this mount started.
    securityStopped:   bool     // Whether a security event interrupted this mount.

    progress: VolumeProgress     // What the job has done, and the way to ask it to stop.
}

impl VaultOperation
{
    // Forgets what the finished operation was asked and what it reported.
    //
    // The task, its timer, and the progress tracker belong to the window rather than to one
    // operation, and the access inputs were already wiped by the worker, so they stay as they are.
    mtd forgetRequest()
    {
        .kind = .None
        .error.reset()
        .volume            = null
        .usedProtection    = false
        .leavesUnprotected = false
        .createHidden      = false
        .protectHidden     = false
        .removesPassword   = false
        .accessChange      = .Password
        .fromStartup       = false
        .securityStopped   = false
        .camouflageOnly    = false
        .size              = 0
        .path.clear()
        .mount.clear()
        .mountLabel.clear()
        .resultKeyFiles.clear()
    }
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
    let texts = appStrings()

    switch err
    {
    case Error as volumeError:
        logDiagnostic(volumeError.message)

        // The last three kinds name a shape the filesystem layer refuses, never a container a
        // reader chose, so a reader can only be told the container is damaged.
        switch #complete volumeError.kind
        {
        case .PasswordRequired:  return texts.msg_PasswordRequired
        case .SizeTooSmall:      return minimumSizeMessage()
        case .PasswordOrDamaged: return texts.msg_ErrPasswordOrDamaged
        case .Corrupted:         return texts.msg_ErrDamaged
        case .NotFound:          return texts.msg_ErrNotFound
        case .AlreadyExists:     return texts.msg_ErrAlreadyExists
        case .AccessDenied:      return texts.msg_ErrAccessDenied
        case .HiddenProtected:   return texts.msg_HiddenProtected
        case .WriteProtected:    return texts.msg_ErrReadOnly
        case .SparseContainer:   return texts.msg_ErrSparse
        case .DiskFull:          return texts.msg_ErrDiskFull
        case .Io:                return texts.msg_ErrIo
        case .Canceled:          return texts.msg_OperationStopped
        case .InvalidInput:      return texts.msg_ErrInvalidRequest
        case .General:           return texts.msg_SystemError
        case .NotDirectory, .IsDirectory, .DirectoryNotEmpty: return texts.msg_ErrDamaged
        }

    case Swag.SystemError as systemError:
        logDiagnostic(systemError.message)
        return texts.msg_SystemError
    }

    return texts.msg_OperationStopped
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

impl MainWindow
{
    // Keep a stable wrapping width; fitToContent measures the tallest translated panel.
    const WindowWidth = 720's32

    // Idle delays the automatic-unmount picker offers, in minutes, and the one it starts on.
    const IdleChoices      = [5'u32, 15, 30, 60]
    const IdleDefaultIndex = 1'u32

    // The page that opens a vault.
    const OpenTabIndex = 1'u32

    // Builds the window: the header, the footer, the create, mount, and drive tabs, and the texts
    // of the active language.
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
        result.showOperation()
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
        for child in .children where child.isLocallyVisible()
        {
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
        if .operation.kind != .None or not .canCreate() do
            return
        .createContainer()
    }

    // Mounts the drive when the open form holds everything it needs.
    mtd submitMount()
    {
        if .operation.kind != .None or not .canMount() do
            return
        .mountContainer()
    }

    // Applies the persisted language, or the language of the account when none was picked.
    mtd applyLanguage()
    {
        discard catch .appearanceButton.setAppearanceLanguage(.language)
    }

    // Applies the persisted standard application palette.
    mtd applyTheme()
    {
        .themeIndex = Math.min(.themeIndex, cast(u32, AppearanceTheme.Dark))
        .appearanceButton.setAppearanceTheme(cast(AppearanceTheme, .themeIndex))
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
        if .operation.kind != .None do
            return
        .createButton.enable(.canCreate())
        .mountButton.enable(.canMount())
        .passwordButton.enable(.canModifyVault())
        .keyFilesButton.enable(.canModifyVault())
        .resizeButton.enable(.canModifyVault())
        .hiddenButton.enable(.canModifyVault())
        .mountedDrives.unmountButton.enable(.mountedDrives.selectedIndex() != Swag.U64.Max)
    }

    // Enables what the running operation leaves usable, and lets the create and resize buttons
    // stop their own operation.
    mtd showOperation()
    {
        let ready    = .operation.kind == .None
        let creating = .operation.kind == .Create
        let resizing = .operation.kind == .Resize

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
        .showOperation()
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

    // Whether a drive is already exposing this container.
    mtd isMounted(path: string)->bool
    {
        for &one in .mountedDrives.drives where one.path == path do
            return true
        return false
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
        switch evt.kind
        {
        case .LanguageChanged: .retranslate()
        case .ThemeChanged where .layoutReady: .fitToContent()
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        catch g_App.saveState()
        .shutdown()
        .wnd.IWnd.onDestroyEvent(evt)
    }
}
