#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// An event whose `Event` base is not its first field, and that counts its drops through `drops`.
struct OffsetOwnedEvent
{
    prefix:     u64 = 42
    using base: Event
    drops:      *u32?
}

impl IEvent for OffsetOwnedEvent {}

impl OffsetOwnedEvent
{
    mtd opDrop()
    {
        if let count = .drops
        {
            Swag.require(.prefix == 42)
            count[] += 1
        }
    }
}

// Every posting entry point snapshots both inline and allocated command identifiers.
#test
{
    var id:   String
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()

    for expected in ["Event.Short", "Event.Command.With.An.Allocated.Identifier"]
    {
        for route in 3
        {
            id = expected
            let before = host.commandCount
            if route == 0
            {
                host.root.postCommandEvent(id.toString())
            }
            else
            {
                let evt = Event.create'CommandEvent()
                evt.id = id.toString()
                if route == 1
                {
                    host.root.postEvent(evt)
                }
                else
                {
                    evt.target = &host.root
                    host.app.postEvent(evt)
                }
            }

            // Keep the source alive and mutate it, so a missed copy fails deterministically.
            id[0] = 'X'
            Swag.require(host.commandCount == before)
            host.pumpPostedEvents()
            Swag.require(host.commandCount == before + 1)
            Swag.require(host.lastCommand == expected)
        }
    }

    let before = host.commandCount
    host.root.postCommandEvent(null)
    host.pumpPostedEvents()
    Swag.require(host.commandCount == before)

    host.root.postCommandEvent("")
    host.pumpPostedEvents()
    Swag.require(host.commandCount == before + 1)
    Swag.require(host.lastCommand == "")
}

// A handler can copy a posted command before dispatch releases the original allocation.
#test
{
    var retained: CommandEvent
    var host:     Testing.HeadlessHost
    host.setup(240, 120)

    host.root.hookOnEvent = func|retained = &retained|(_, evt)
    {
        if evt is CommandEvent as command
        {
            retained[] = command[]
            return true
        }

        return false
    }

    for expected in ["Event.Short", "Event.Command.With.An.Allocated.Identifier"]
    {
        var id = String.from(expected)
        host.root.postCommandEvent(id.toString())
        id[0] = 'X'
        host.pumpPostedEvents()
        Swag.require(retained.id == expected)

        var copied = retained
        Swag.require(copied.id == expected)
        Swag.require(copied.id.buffer != retained.id.buffer)
        var moved = #move copied
        Swag.require(moved.id == expected)

        // Posting a copy snapshots a view that already belongs to that same event.
        let reposted = Event.create'CommandEvent()
        reposted[] = moved
        host.root.postEvent(reposted)
        host.pumpPostedEvents()
        Swag.require(retained.id == expected)

        // Replacing the public view does not make it refer to the old owned identifier again.
        retained.id = "Event.Reassigned"
        var reassigned = retained
        Swag.require(reassigned.id == "Event.Reassigned")
        var movedReassigned = #move reassigned
        Swag.require(movedReassigned.id == "Event.Reassigned")
    }
}

// Synchronous events still borrow their identifier; the headless recorder owns its observation.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()

    var id     = String.from("Event.Borrowed")
    var evt    = CommandEvent{id: id.toString()}
    var copied = evt
    id[0] = 'X'
    Swag.require(copied.id == "Xvent.Borrowed")

    host.root.sendEvent(&copied)
    id[0] = 'Y'
    Swag.require(host.commandCount == 1)
    Swag.require(host.lastCommand == "Xvent.Borrowed")
}

// Closing on a command retains the observed identifier after synchronous delivery too.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.closeOnCommand("Event.Close")

    var id = String.from("Event.Close")
    host.root.sendCommandEvent(id.toString())
    id[0] = 'X'
    Swag.require(host.closed and host.commandCount == 1)
    Swag.require(host.lastCommand == "Event.Close")
}

// Queue ownership uses the complete allocation even when Event is not its first field.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)

    var drops: u32
    let evt = Event.create'OffsetOwnedEvent()
    evt.drops = &drops
    let base: *Event = evt
    Swag.require(cast(*void, base) != cast(*void, evt))
    Swag.require((catch cast(*OffsetOwnedEvent?, base)) == evt)
    host.root.postEvent(evt)
    host.pumpPostedEvents()
    Swag.require(drops == 1)
}

// A heap command-state event reports its dynamic type and keeps every field a query fills.
#test
{
    let evt = Event.create'CommandStateEvent()
    defer Memory.delete(evt)
    let view: IEvent = evt
    Swag.require(Swag.kindOf(view) == #typeof(CommandStateEvent))
    Swag.require((catch cast(*CommandStateEvent?, view)) == evt)
    Swag.require(not evt.accepted)

    evt.kind          = .Apply
    evt.id            = Dialog.BtnOk
    evt.updatedFields = CommandStateEvent.UpdatedFields.Disabled | .Name
    evt.renderingHint = .ExclusiveGroup
    evt.disabled      = true
    evt.name          = "Ok"

    Swag.require(evt.kind == .Apply)
    Swag.require(evt.id == "Dialog.BtnOk")
    Swag.require(evt.updatedFields.has(.Disabled))
    Swag.require(evt.updatedFields.has(.Name))
    Swag.require(not evt.updatedFields.has(.Shortcut))
    Swag.require(evt.renderingHint.has(.ExclusiveGroup))
    Swag.require(evt.disabled)
    Swag.require(evt.name == "Ok")
}

// A mouse event keeps its kind, position, motion, and modifiers.
#test
{
    var mouseEvt: MouseEvent
    mouseEvt.kind       = .Move
    mouseEvt.surfacePos = {10, 20}
    mouseEvt.delta      = {-3, 4}
    mouseEvt.modifiers  = Input.KeyModifiers.Control | .Shift

    Swag.require(mouseEvt.kind == .Move)
    Swag.require(mouseEvt.surfacePos == Math.Point{10, 20})
    Swag.require(mouseEvt.delta == Math.Point{-3, 4})
    Swag.require(mouseEvt.modifiers == .CtrlShift)
}

// Heap command, resize, and move events report their dynamic type and keep their payload.
#test
{
    let cmd = Event.create'CommandEvent()
    defer Memory.delete(cmd)
    cmd.id = Dialog.BtnCancel
    Swag.require(Swag.kindOf(cast(IEvent, cmd)) == #typeof(CommandEvent))
    Swag.require(cmd.id == "Dialog.BtnCancel")
    Swag.require(cmd.source == null)

    let resize = Event.create'ResizeEvent()
    defer Memory.delete(resize)
    resize.oldSize = {640, 480}
    Swag.require(Swag.kindOf(cast(IEvent, resize)) == #typeof(ResizeEvent))
    Swag.require(resize.oldSize == Math.Point{640, 480})

    let move = Event.create'MoveEvent()
    defer Memory.delete(move)
    move.oldPos = {12, 34}
    Swag.require(Swag.kindOf(cast(IEvent, move)) == #typeof(MoveEvent))
    Swag.require(move.oldPos == Math.Point{12, 34})
}

// Paint, focus, state, and notification events start from their defaults and keep the kind they are given.
#test
{
    var paint: PaintEvent
    Swag.require(paint.kind == .Content)

    var focus: FocusEvent
    Swag.require(focus.canChangeFocus)
    focus.kind = .CanLose
    focus.canChangeFocus = false
    Swag.require(focus.kind == .CanLose)
    Swag.require(not focus.canChangeFocus)

    var state: StateEvent
    state.kind = .Hide
    Swag.require(state.kind == .Hide)

    var notify: NotifyEvent
    notify.kind = .ThemeChanged
    Swag.require(notify.kind == .ThemeChanged)
}

// Key, system-user, and system-command events keep what their sender wrote.
#test
{
    var key: KeyEvent
    key.kind      = .Character
    key.character = 'x'
    key.modifiers = .Alt
    Swag.require(key.kind == .Character)
    Swag.require(key.character == 'x')
    Swag.require(key.modifiers == .Alt)

    var sysUser: SysUserEvent
    sysUser.kind      = .CustomMessage
    sysUser.messageId = 42
    sysUser.param     = 22
    Swag.require(sysUser.kind == .CustomMessage)
    Swag.require(sysUser.messageId == 42)
    Swag.require(sysUser.param == 22)

    sysUser.kind       = .TrayIcon
    sysUser.trayAction = .ContextMenu
    Swag.require(sysUser.trayAction == .ContextMenu)

    var sysCommand: SysCommandEvent
    sysCommand.kind = .Restore
    Swag.require(sysCommand.kind == .Restore)
}

var g_TaskEventsSeen: u32
var g_RecordDone:     bool     // The watched task is a `Swag.Task'u32`, and the watcher records whether it is done.
var g_DoneWhenSeen:   bool

// A window that records the tasks it is told have finished.
struct TaskWatcher
{
    using wnd: Wnd
    lastTask:  const *void?
}

impl IWnd for TaskWatcher
{
    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        g_TaskEventsSeen += 1
        if g_RecordDone do
            g_DoneWhenSeen = cast(const *Swag.Task'u32, evt.task).isDone()
        .lastTask = evt.task
    }
}

// Runs until `gate` is raised.
func waitForGate(gate: const *Swag.AtomicFlag)->u32
{
    while not gate.isRaised() do
        Threading.Thread.sleep(1'ms)
    return 2
}

// Raises `gate` after `milliseconds`, or as soon as it is asked to stop.
func raiseGateLater(gate: *Swag.AtomicFlag, milliseconds: u32)
{
    for milliseconds
    {
        if Swag.isCancelled() do
            return
        Threading.Thread.sleep(1'ms)
    }

    discard gate.raise()
}

// A finished task reaches the window that watches it once, during a frame of the GUI thread.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)

    g_TaskEventsSeen = 0
    let watcher = Wnd.create'TaskWatcher(&host.root)
    var task: Swag.Task'u32
    task.submit(func()->u32 => 3, watcher.taskNotifier(&task))
    task.wait()
    Swag.require(g_TaskEventsSeen == 0)

    host.pumpPostedEvents()
    Swag.require(g_TaskEventsSeen == 1 and watcher.lastTask == &task)
    let value = expect task.take()
    Swag.require(value == 3)

    host.pumpPostedEvents()
    Swag.require(g_TaskEventsSeen == 1)
}

// A notification runs just before its task reads as done. An event the window receives can
// therefore come before that moment; delivery waits it out, so the outcome is ready to take.
#test
{
    // The submission has to run on a worker while the window handles the event, and a second
    // worker has to end it.
    if Swag.workerCount() < 2 do
        return

    var host: Testing.HeadlessHost
    host.setup(240, 120)

    g_TaskEventsSeen = 0
    let watcher = Wnd.create'TaskWatcher(&host.root)
    var gate:    Swag.AtomicFlag
    var release: Swag.Task
    var task:    Swag.Task'u32
    g_RecordDone = true
    defer g_RecordDone = false

    task.submit(func|&gate|()->u32 => waitForGate(&gate))
    let notify = watcher.taskNotifier(&task)
    notify()
    release.submit(func|&gate|() { raiseGateLater(&gate, 20) })

    host.pumpPostedEvents()
    Swag.require(g_TaskEventsSeen == 1 and g_DoneWhenSeen)
    let value = expect task.take()
    Swag.require(value == 2)
}

// An event about a submission the window already collected arrives without waiting for the task's
// next submission.
#test
{
    if Swag.workerCount() < 2 do
        return

    var host: Testing.HeadlessHost
    host.setup(240, 120)

    g_TaskEventsSeen = 0
    let watcher = Wnd.create'TaskWatcher(&host.root)
    var gate:    Swag.AtomicFlag
    var release: Swag.Task
    var task:    Swag.Task'u32
    g_RecordDone = true
    defer g_RecordDone = false

    task.submit(func()->u32 => 1)
    task.wait()
    let notify = watcher.taskNotifier(&task)
    notify()
    discard expect task.take()

    // Should delivery wait for this submission, the gate still opens and the test fails instead
    // of hanging.
    task.submit(func|&gate|()->u32 => waitForGate(&gate))
    release.submit(func|&gate|() { raiseGateLater(&gate, 2000) })

    host.pumpPostedEvents()
    Swag.require(g_TaskEventsSeen == 1 and not g_DoneWhenSeen)
    discard gate.raise()
    release.cancel()
    let value = expect task.take()
    Swag.require(value == 2)
}

// A window whose destruction completed before the event is delivered never receives it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)

    g_TaskEventsSeen = 0
    let watcher = Wnd.create'TaskWatcher(&host.root)
    var task: Swag.Task
    task.submit(func() {}, watcher.taskNotifier(&task))
    task.wait()

    watcher.destroy()
    host.pumpDestroyEvents()
    host.pumpPostedEvents()
    Swag.require(g_TaskEventsSeen == 0)
}
