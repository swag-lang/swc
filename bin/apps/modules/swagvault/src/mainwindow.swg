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

// Emphasis of the notice line, from what the latest step left behind.
enum StatusTone
{
    Idle        // Nothing is running and nothing has failed.
    Active      // Work is running, or a drive is mounted.
    Stopped     // The latest operation stopped.
}

// What the notice line under the title of the list is currently reporting.
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

// The pages of the window. One is on screen at a time; the list is where the window opens and
// where every other page leads back.
enum WindowPage
{
    List         // The vaults, the chosen locked one unfolded to unlock it.
    Create       // The form that makes a new vault.
    Progress     // A creation, a resize or a camouflage refresh while it runs.
    Options      // Privacy and automatic unmounting.
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

// Settings of the last mount that completed successfully, as earlier versions saved them.
//
// The list of vaults now remembers every vault with its drive and its read-only choice; this is
// read once so that the vault a reader last mounted is still on the list after an update.
struct MountSettings
{
    path:     String     // Container file that was mounted.
    drive:    String     // Stable backend destination identifier; the name preserves saved-state compatibility.
    readOnly: bool       // Whether the mount was for reading alone.
}

// A vault the list shows.
//
// Only what prepares the next mount is kept: where the container is, the drive it last came up
// on, and whether it was opened for reading alone. A credential is deliberately absent: passwords
// and key-file paths live only in their controls and the operation that consumes them.
struct KnownVault
{
    path:     String     // Container file of the vault.
    drive:    String     // Stable backend destination identifier the vault was last mounted on, or empty.
    readOnly: bool       // Whether the vault was last mounted for reading alone.
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
    fromStartup:       bool     // Whether the mount came from the startup list rather than from the list of vaults.
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
//
// The window is the list of vaults. Creating a vault, following a long operation and setting the
// privacy policy are pages that lead back to it, and every command is an entry of the lens.
struct MainWindow
{
    using wnd: Wnd

    // The pages, the door to every command, and the line that teaches it.
    late
    {
        appearanceButton: *AppearanceButton
        lens:             *Lens.View
        hintLine:         *HintLine
        list:             *VaultList
        createPage:       *CreatePage
        progressPage:     *ProgressPage
        optionsPage:      *OptionsPage
    }

    // The controls every operation reads, named here once: the access of the unfolded vault, and
    // the form of the create page.
    late
    {
        mountPassword: *PasswordEdit
        drive:         *ComboBox
        readOnly:      *CheckButton
        mountButton:   *PushButton

        createPath:      *EditBox
        createSize:      *EditBox
        createUnit:      *Tab
        createPassword:  *PasswordEdit
        confirmPassword: *PasswordEdit
        createButton:    *PushButton
        browseCreate:    *PushButton
    }

    // The switches of the privacy page.
    late
    {
        privacyModeControl: *ToggleButton
        unmountOnLock:      *ToggleButton
        unmountOnSuspend:   *ToggleButton
        unmountOnIdle:      *ToggleButton
        idleTimeout:        *IconButton
    }

    page:        WindowPage
    layoutReady: bool

    // The vaults the list shows, mounted or locked, newest first. With privacy mode on, the list
    // keeps only the vaults that are mounted or being unlocked, and none of it reaches the disk.
    vaults:     Array'KnownVault
    chosenPath: String     // Container of the vault the list has chosen, or empty.

    // Key files stated on the unfolded vault and on the create page. Like the passwords, they are
    // never settings.
    unlockKeyFiles: Array'String
    createKeyFiles: Array'String

    // Whether the next mount of the chosen vault protects its hidden volume. It is asked again at
    // every mount, so it is never a setting either.
    protectHiddenOnMount: bool

    // Not `undefined`: the model owns the drive list, and an owning array has to be constructed
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
    startupWaiting:  String     // Protected startup vault unfolded in the list for its access, or empty.
    startupTimer:    *Timer?
    securityTimer:   *Timer?
    securityMonitor: AutoUnmountMonitor

    mountDestinations: Array'MountDestination
    autoUnmount:       AutoUnmountSettings
    securityEpoch:     u64

    // What the notice line says, plus the two values its wording interpolates: the drive
    // letter of the mounted message and the percentage of the randomizing one.
    statusMessage:  StatusMessage
    statusDrive:    String
    statusProgress: s32

    // How long the running creation or resize has taken, for the time its page says is left.
    progressClock: Time.Stopwatch

    // Language tag applied at start, or empty to follow the language of the account.
    //
    // It holds [[Gui.ReferenceLanguage]] until the user picks something else: Swag Vault is an
    // English application that speaks other languages on request, not one that guesses.
    language:   String
    themeIndex: u32
}

// The sentence a reader sees for `err`, in the active language, with the native code of the
// failure under it when one came with it. Where it was raised goes to the debugger output.
//
// Returns an owned string, not a view: one kind formats its sentence, and a view into that
// temporary would dangle as soon as the statement building it ends. The constant sentences are
// copied out of the string table for the same contract.
func caughtMessage(err: any?)->String
{
    let texts = appStrings()

    switch err
    {
    case Error as volumeError:
        logDiagnostic(volumeError)
        return withErrorCode(kindMessage(volumeError.kind), volumeError.code)

    case Swag.SystemError as systemError:
        return withErrorCode(texts.msg_SystemError, systemError.errorID)
    }

    return texts.msg_OperationStopped
}

// The sentence that tells a reader what a failure of `kind` means for them. A kind that means
// nothing to a reader, such as a metadata record declaring an implausible entry count, reads as
// the generic damaged-container wording: the detail is for a report, not for someone trying to
// mount a drive.
func kindMessage(kind: ErrorKind)->String
{
    let texts = appStrings()

    // The last three kinds name a shape the filesystem layer refuses, never a container a reader
    // chose, so a reader can only be told the container is damaged.
    switch #complete kind
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
    case .Elevated:          return texts.msg_ErrElevated
    case .DriverUnavailable: return texts.msg_ErrDriverUnavailable
    case .Canceled:          return texts.msg_OperationStopped
    case .InvalidInput:      return texts.msg_ErrInvalidRequest
    case .General:           return texts.msg_SystemError
    case .NotDirectory, .IsDirectory, .DirectoryNotEmpty: return texts.msg_ErrDamaged
    }
}

// Adds the native code of a failure under its sentence, for whoever reports it; a failure
// without one keeps the sentence alone.
func withErrorCode(message: String, code: u64)->String
{
    if not code do
        return message
    return Format.toString("%\n\n%", message, Format.toString(appStrings().msg_ErrorCode, code))
}

// Says the smallest capacity a container can have, in whole mebibytes.
func minimumSizeMessage()->String
{
    const Mebibyte = 1024'u64 * 1024
    return Format.toString(appStrings().msg_SizeMinimum, (MinimumSize + Mebibyte - 1) / Mebibyte)
}

// Sends where a failure was raised to the debugger output.
//
// It is deliberately not shown: the reader gets the sentence for the kind, and this is the
// line whoever reads a report needs to tell two failures of the same kind apart.
private func logDiagnostic(err: const *Error)
{
    // Built as one owned string: it carries its terminator, which is what the debugger
    // output expects, and a view over a longer buffer would not.
    let fileName = Path.fileName(err.location.fileName orelse "") orelse ""
    Debugger.log(Format.toString("Swag Vault: % %:% 0x%{X}\n", err.kind, fileName, err.location.lineStart + 1, err.code))
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
    let texts = appStrings()
    if bytes >= Gibibyte and not (bytes % Gibibyte) do
        return Format.toString("% %", bytes / Gibibyte, texts.ui_UnitGiB)
    return Format.toString("% %", (bytes + Mebibyte - 1) / Mebibyte, texts.ui_UnitMiB)
}

// Reads a capacity field and its unit, or says why the pair cannot be used.
//
// Only what the number itself makes impossible is judged here — an empty field, a value that
// no longer fits, a zero. What is too small or too small *for this container* belongs to the
// operation that asked, because the two do not refuse for the same reason.
func parseCapacity(text: string, unitIndex: u32)->ContainerSize
{
    var result: #returntype

    var parseErrorOutcome: Swag.Error
    var parsed: #decltype(expect StrConv.parseU64(text))
    catch { parsed = try StrConv.parseU64(text) } as parseErrorOutcome
    let parseError = parseErrorOutcome.value()
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
    // The size the window opens at, and the smallest it can be made: the pages are measured
    // columns, so below that width a column would no longer keep its margins.
    const DefaultWidth  = 1040's32
    const DefaultHeight = 720's32
    const MinWidth      = 720's32
    const MinHeight     = 660's32

    // Idle delays the automatic-unmount picker offers, in minutes, and the one it starts on.
    const IdleChoices      = [5'u32, 15, 30, 60]
    const IdleDefaultIndex = 1'u32

    // How many locked vaults the list keeps. Mounted vaults are always on it.
    const RememberedVaults = 16'u64

    // Builds the window: the pages, the lens and its hint, and the texts of the active language.
    func create(parent: *Wnd)->*MainWindow
    {
        let result  = Wnd.create'MainWindow(parent, "vault.mainWindow")
        let surface = unwrap result.surface
        surface.setView(result)
        surface.minSize        = {MinWidth, MinHeight}
        result.backgroundStyle = .View
        result.language        = ReferenceLanguage

        result.createAppearanceButton()
        result.createPages()
        result.createLens()
        Lens.Launcher.create(result, VaultCommands.Lens)
        result.createHint()
        result.fillDriveChoice()
        result.applyLanguage()
        result.applyPrivacyControl()
        result.applyAutoUnmountControls()
        result.showPage(.List, animate: false)
        result.showOperation()
        result.setStatus(.Ready)
        result.layoutReady = true
        return result
    }

    // Creates the appearance action, hidden: the theme, the language and About are lens entries,
    // and this control stays the one owner of the choice and of its persistence.
    mtd createAppearanceButton()
    {
        with .appearanceButton = AppearanceButton.create(unwrap .surface, "vault.appearance")
        {
            .hide()
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

            .sigAboutRequested += func|window = me|(_)
            {
                window.showAbout()
            }
        }
    }

    // Creates the four pages, and names the controls every operation reads.
    mtd createPages()
    {
        .list         = VaultList.create(me)
        .createPage   = CreatePage.create(me)
        .progressPage = ProgressPage.create(me)
        .optionsPage  = OptionsPage.create(me)

        .mountPassword = .list.card.password
        .drive         = .list.card.drive
        .readOnly      = .list.card.readOnly
        .mountButton   = .list.card.mount

        .createPath      = .createPage.path
        .createSize      = .createPage.size
        .createUnit      = .createPage.unit
        .createPassword  = .createPage.password
        .confirmPassword = .createPage.confirm
        .createButton    = .createPage.createAction
        .browseCreate    = .createPage.browse

        .privacyModeControl = .optionsPage.privacy.toggle
        .unmountOnLock      = .optionsPage.lock.toggle
        .unmountOnSuspend   = .optionsPage.suspend.toggle
        .unmountOnIdle      = .optionsPage.idle.toggle
        .idleTimeout        = .optionsPage.timeout
    }

    // Creates the line teaching the door, near the bottom edge.
    mtd createHint()
    {
        .hintLine = HintLine.create(me, "vault.hint")
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

        // The driver that shows a vault as a drive keeps its notice where the product's own is.
        let dialog = AboutDlg.createApplication(unwrap .surface, about)
        dialog.addSection("WinFsp", appStrings().ui_AboutThirdParty)
        discard dialog.doModal()
    }

    // Brings `page` up, from the side it is reached from, and gives the keyboard to the first
    // thing there is to do on it.
    mtd showPage(page: WindowPage, animate = true)
    {
        let outgoing = .pageWnd(.page)
        let incoming = .pageWnd(page)
        .page = page

        if animate and outgoing != incoming
        {
            discard .app().animator.transitionPage(outgoing, incoming, page == .List ? -1'f32 : 1)
        }
        else
        {
            for one in [WindowPage.List, WindowPage.Create, WindowPage.Progress, WindowPage.Options] do
                .pageWnd(one).show(one == page)
        }

        .applyLayout()
        .refreshHint()
        .setInitialFocus(.initialStop())
        .initialStop()?.setFocus()
    }

    // Returns the window that shows `page`.
    mtd pageWnd(page: WindowPage)->*Wnd
    {
        switch #complete page
        {
        case .List:     return .list.scroll
        case .Create:   return .createPage
        case .Progress: return .progressPage
        case .Options:  return .optionsPage
        }
    }

    // The stop a page opens on: the first thing there is to do on it.
    mtd initialStop()->*Wnd?
    {
        switch #complete .page
        {
        case .List:
            if .chosenLockedPath().count != 0 do
                return .mountPassword
            if not .list.rows.isEmpty() do
                return .list.rows[0]
            return .list.newVault

        case .Create:
            return .createPath

        case .Progress:
            return .progressPage.stop

        case .Options:
            return .privacyModeControl
        }
    }

    // Teaches the door while the list is on screen, and on the privacy page, where privacy mode
    // empties the list, says where the vaults open from instead. While a vault is unfolded the
    // hand is already at work, and the line steps aside so the actions under the list keep their room.
    mtd refreshHint()
    {
        .hintLine.clearHints()
        switch .page
        {
        case .List where .chosenPath.isEmpty(): .hintLine.addHint(Input.formatKeyShortcut(.Control, .Space), appStrings().ui_HintList)
        case .Options where .privacyMode:       .hintLine.addHint(Input.formatKeyShortcut(.Control, .Space), appStrings().ui_HintPrivacy)
        }

        .hintLine.show(not .hintLine.hints.isEmpty())
    }

    // Applies the persisted language, or the language of the account when none was picked.
    mtd applyLanguage()
    {
        discard catch .appearanceButton.setAppearanceLanguage(.language)
    }

    // Applies the persisted standard application palette.
    mtd applyTheme()
    {
        .themeIndex = Math.min(.themeIndex, cast(u32, AppearanceTheme.System))
        .appearanceButton.setAppearanceTheme(cast(AppearanceTheme, .themeIndex))
    }

    // Returns the vault the list knows at `path`, or null.
    mtd findVault(path: string)->*KnownVault?
    {
        for &one in .vaults where one.path == path do
            return one
        return null
    }

    // Puts the container at `path` on the list, newest first, and keeps a remembered list to its
    // length.
    //
    // With privacy mode on, nothing is pruned here: the vault is being opened or mounted, and the
    // list lets it go once it is neither.
    mtd addVault(path: string)
    {
        if .findVault(path) do
            return
        .vaults.insertAt(0, KnownVault{path: path})
        if not .privacyMode do
            .pruneVaults()
    }

    // Keeps the list to what it may hold.
    //
    // With privacy mode on, a vault stays only while it is mounted or being unlocked: nothing of a
    // locked vault outlives the moment it was asked for. Otherwise the oldest locked vaults go
    // first once the list is longer than it keeps.
    mtd pruneVaults()
    {
        var locked = 0'u64
        var index  = 0'u64
        while index < .vaults.count
        {
            let path = .vaults[index].path.toString()
            let kept = .isMounted(path) or .chosenPath == path
            if kept
            {
                index += 1
                continue
            }

            locked += 1
            if .privacyMode or locked > RememberedVaults
            {
                .vaults.removeAtOrdered(index)
                continue
            }

            index += 1
        }
    }

    // Returns the path of the chosen vault when it is locked, the one the list unfolds; empty
    // when the chosen vault is mounted or nothing is chosen.
    mtd chosenLockedPath()->string
    {
        if .chosenPath.isEmpty() or .isMounted(.chosenPath) do
            return ""
        return .chosenPath
    }

    // Chooses the vault at `path`: a locked one unfolds to be unlocked, a mounted one becomes the
    // one the commands of the lens act on.
    mtd chooseVault(path: string)
    {
        if .page != .List do
            .showPage(.List)
        if .chosenPath == path
        {
            if .chosenLockedPath().count != 0 do
                .mountPassword.setFocus()
            return
        }

        // The access typed for one vault is never offered to another.
        .forgetAccess()
        .chosenPath = path
        if let vault = .findVault(path)
        {
            .readOnly.setState(vault.readOnly ? .Checked : .Unchecked)
            discard .selectMountPoint(vault.drive)
        }

        .pruneVaults()
        .refreshVaults()
        if .chosenLockedPath().count != 0 do
            .mountPassword.setFocus()
        .skipStartupVault()
    }

    // Folds the unfolded vault, and forgets the access typed for it.
    mtd foldVault()
    {
        if .chosenPath.isEmpty() do
            return
        .forgetAccess()
        .chosenPath.clear()
        .pruneVaults()
        .refreshVaults()
        .skipStartupVault()
    }

    // Wipes the access stated for the chosen vault: its password, its key files and the hidden
    // protection of its next mount.
    mtd forgetAccess()
    {
        .mountPassword.clear()
        .unlockKeyFiles.clear()
        .protectHiddenOnMount = false
    }

    // Says the list again from the vaults and the drives, and puts the actions in step with it.
    mtd refreshVaults()
    {
        .mountedDrives.refreshSpace()
        .list.refresh()
        .refreshActions()
        .refreshHint()
    }

    // The mono line under a vault's name: where its drive is and how it is open, or where its
    // container is and that it is locked.
    mtd vaultIdentity(path: string)->String
    {
        let texts = appStrings()
        var result: #returntype

        if let drive = .mountedDrives.find(path)
        {
            result = Format.toString(texts.ui_StateMounted, drive.mountLabel)
            result += Format.toString(" · %", capacityText(drive.totalBytes))
            result += Format.toString(" · %", drive.readOnly ? texts.ui_StateReadOnly : texts.ui_StateReadWrite)
            if drive.protectHidden do
                result += Format.toString(" · %", texts.ui_StateProtected)
            if drive.atStartup do
                result += Format.toString(" · %", texts.ui_StateAtStartup)
            return result
        }

        result = Path.directoryName(path) orelse ""
        if not result.isEmpty() do
            result += " · "
        result += texts.ui_StateLocked
        if .startupIndex(path) != Swag.U64.Max do
            result += Format.toString(" · %", texts.ui_StateAtStartup)
        if .chosenPath == path and .protectHiddenOnMount do
            result += Format.toString(" · %", texts.ui_StateProtected)
        return result
    }

    // Whether the create page holds everything a container needs.
    //
    // Neither password is read here: an empty pair is a vault that opens without one, and a
    // mismatch is reported when the button is pressed, because a form that goes down as soon as
    // the two differ would go down on every keystroke of the second one.
    mtd canCreate()->bool => .createPath.text().count != 0 and .createSize.text().count != 0

    // Whether the unfolded vault holds everything a drive needs.
    //
    // The password is not read: a container that opens without one is answered by an empty
    // field, and a wrong password is reported by the container, not by the form.
    mtd canMount()->bool => .chosenLockedPath().count != 0 and not .selectedMountPoint().isEmpty()

    // Whether a vault is chosen that the commands changing a vault can act on.
    mtd canModifyVault()->bool => not .chosenPath.isEmpty()

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
    }

    // Enables what the running operation leaves usable.
    //
    // A creation and a resize run on their own page, whose one action stops them; every other
    // operation leaves the list on screen with its forms down until it ends.
    mtd showOperation()
    {
        let ready = .operation.kind == .None
        let card  = &.list.card

        .createPage.form.enable(ready)
        .createPage.actions.enable(ready)
        .createButton.enable(ready and .canCreate())
        card.form.enable(ready)
        card.options.enable(ready)
        .mountButton.enable(ready and .canMount())
        .list.newVault.enable(ready)
        .list.openFile.enable(ready)
        for row in .list.rows do
            row.refresh()
        .list.card.header.refresh()

        .progressPage.stop.setText(.operation.kind == .Resize ? appStrings().ui_StopResizing : appStrings().ui_StopCreating)
        .progressPage.stop.enable(not ready and not .operation.progress.isCanceled())
        .progressPage.arrange()
    }

    // Says everything the window said at construction, in the language now active.
    //
    // Only text set once by hand needs this: the buttons and the wrapped paragraphs
    // re-measure themselves from the new wording, so the surface re-arranges around what
    // the language actually costs instead of around the widths English needed.
    mtd retranslate()
    {
        .surface?.setTitle(appStrings().ui_WindowTitle)
        .createPage.retranslate()
        .optionsPage.retranslate()
        .applyAutoUnmountControls()
        .list.retranslate()
        .showOperation()
        .refreshStatus()
        .refreshHint()
        .invalidate()
    }

    // Whether a drive is already exposing this container.
    mtd isMounted(path: string)->bool => .mountedDrives.find(path) != null

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
        // the list is exactly as real to Windows as one that did.
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
        .unlockKeyFiles.clear()
        .createKeyFiles.clear()
        .operation.error.reset()
    }
}

impl IWnd for MainWindow
{
    // Takes a container dropped anywhere on the window that no field claimed first.
    //
    // Dropping one file says "open this" regardless of its name: the container format, not a
    // filename extension, identifies a vault. The window puts it on the list and unfolds it, which
    // leaves the reader one access entry away from a drive. A drop that lands on a path field is
    // that field's own business and never reaches here.
    mtd impl onDragDropEvent(evt: *DragDropEvent)
    {
        let path = evt.data.singleFile()
        if not path
        {
            evt.accepted = false
            return
        }

        if evt.kind == .Drop do
            .openVault(path)

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
            catch evt.serializer.serialize("MainWindow.vaults", &me.vaults)
            catch evt.serializer.serialize("MainWindow.startupVaults", &me.startupVaults)

            // The last mount an earlier version remembered joins the list once.
            if evt.serializer.isReading()
            {
                var legacy: MountSettings
                catch evt.serializer.serialize("MainWindow.mountSettings", &legacy)
                if not legacy.path.isEmpty() and not .findVault(legacy.path) do
                    .vaults.add(KnownVault{legacy.path, legacy.drive, legacy.readOnly})
            }
        }

        catch evt.serializer.serialize("MainWindow.autoUnmount", &me.autoUnmount)

        if evt.serializer.isReading()
        {
            if .privacyMode do
                .clearPrivateState()
            .applyPrivacyControl()
            .applyAutoUnmountControls()
            .refreshVaults()
        }
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        switch evt.kind
        {
        case .LanguageChanged: .retranslate()
        case .ThemeChanged where .layoutReady: .refreshVaults()
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onComputeStateEvent(evt: *CommandStateEvent)
    {
        if not .computeCommandState(evt) do
            evt.accepted = false
    }

    mtd impl onCommandEvent(evt: *CommandEvent)
    {
        evt.accepted = .runCommand(evt.id)
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        catch g_App.saveState()
        .shutdown()
        .wnd.IWnd.onDestroyEvent(evt)
    }
}
