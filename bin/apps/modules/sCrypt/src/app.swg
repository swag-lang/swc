using Core, Gui

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

// Owns the complete application state. The UI thread owns this object; long
// operations use `operation` and report their result back through the timer.
struct MainWindow
{
    using wnd: Wnd

    #[Swag.Late]
    {
        createPath:      *EditBox
        createSize:      *EditBox
        createUnit:      *ComboBox
        createPassword:  *PasswordEdit
        confirmPassword: *PasswordEdit
        createButton:    *PushButton
        mountPath:       *EditBox
        drive:           *ComboBox
        mountPassword:   *PasswordEdit
        mountButton:     *PushButton
        unmountButton:   *PushButton
        status:          *Label
    }

    fileDlgState: FileDlgState
    mounted:      SCrypt.Platform.MountedVolume
    state:        AppState
    shuttingDown: bool

    operation:         Jobs.Job
    operationKind:     OperationKind
    operationTimer:    #null *Timer
    operationError:    #null any
    operationPath:     String
    operationMount:    String
    operationSize:     u64
    operationPassword: Array'u8
}

internal func caughtMessage(err: #null any)->string
{
    switch err
    {
    case SCrypt.Error:     return (cast(SCrypt.Error) err).message orelse "sCrypt error."
    case Swag.SystemError: return (cast(Swag.SystemError) err).message orelse "System error."
    }

    return "The operation stopped."
}

internal func runMainWindowOperation(data: #null *void)
{
    let window = cast(*MainWindow) (notnull data)
    window.runOperation()
}

impl IWnd for MainWindow
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .operationTimer and Jobs.isDone(&.operation) do
            .finishOperation()
        .wnd.IWnd.onTimerEvent(evt)
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        .shutdownInternal()
        .wnd.IWnd.onDestroyEvent(evt)
    }
}
