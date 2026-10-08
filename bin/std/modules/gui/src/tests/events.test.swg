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
            Swag.assert(.prefix == 42)
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
    defer host.shutdown()
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
            Swag.assert(host.commandCount == before)
            host.pumpPostedEvents()
            Swag.assert(host.commandCount == before + 1)
            Swag.assert(host.lastCommand == expected)
        }
    }

    let before = host.commandCount
    host.root.postCommandEvent(null)
    host.pumpPostedEvents()
    Swag.assert(host.commandCount == before)

    host.root.postCommandEvent("")
    host.pumpPostedEvents()
    Swag.assert(host.commandCount == before + 1)
    Swag.assert(host.lastCommand == "")
}

// A handler can copy a posted command before dispatch releases the original allocation.
#test
{
    var retained: CommandEvent
    var host:     Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()

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
        Swag.assert(retained.id == expected)

        var copied = retained
        Swag.assert(copied.id == expected)
        Swag.assert(copied.id.buffer != retained.id.buffer)
        var moved = #move copied
        Swag.assert(moved.id == expected)

        // Posting a copy snapshots a view that already belongs to that same event.
        let reposted = Event.create'CommandEvent()
        reposted[] = moved
        host.root.postEvent(reposted)
        host.pumpPostedEvents()
        Swag.assert(retained.id == expected)

        // Replacing the public view does not make it refer to the old owned identifier again.
        retained.id = "Event.Reassigned"
        var reassigned = retained
        Swag.assert(reassigned.id == "Event.Reassigned")
        var movedReassigned = #move reassigned
        Swag.assert(movedReassigned.id == "Event.Reassigned")
    }
}

// Synchronous events still borrow their identifier; the headless recorder owns its observation.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.recordCommands()

    var id     = String.from("Event.Borrowed")
    var evt    = CommandEvent{id: id.toString()}
    var copied = evt
    id[0] = 'X'
    Swag.assert(copied.id == "Xvent.Borrowed")

    host.root.sendEvent(&copied)
    id[0] = 'Y'
    Swag.assert(host.commandCount == 1)
    Swag.assert(host.lastCommand == "Xvent.Borrowed")
}

// Closing on a command retains the observed identifier after synchronous delivery too.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.closeOnCommand("Event.Close")

    var id = String.from("Event.Close")
    host.root.sendCommandEvent(id.toString())
    id[0] = 'X'
    Swag.assert(host.closed and host.commandCount == 1)
    Swag.assert(host.lastCommand == "Event.Close")
}

// Queue ownership uses the complete allocation even when Event is not its first field.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()

    var drops: u32
    let evt = Event.create'OffsetOwnedEvent()
    evt.drops = &drops
    let base: *Event = evt
    Swag.assert(cast(*void, base) != cast(*void, evt))
    Swag.assert((catch cast(*OffsetOwnedEvent?, base)) == evt)
    host.root.postEvent(evt)
    host.pumpPostedEvents()
    Swag.assert(drops == 1)
}

// A heap command-state event reports its dynamic type and keeps every field a query fills.
#test
{
    let evt = Event.create'CommandStateEvent()
    defer Memory.delete(evt)
    let view: IEvent = evt
    Swag.assert(Swag.kindOf(view) == #typeof(CommandStateEvent))
    Swag.assert((catch cast(*CommandStateEvent?, view)) == evt)
    Swag.assert(not evt.accepted)

    evt.kind          = .Apply
    evt.id            = Dialog.BtnOk
    evt.updatedFields = CommandStateEvent.UpdatedFields.Disabled | .Name
    evt.renderingHint = .ExclusiveGroup
    evt.disabled      = true
    evt.name          = "Ok"

    Swag.assert(evt.kind == .Apply)
    Swag.assert(evt.id == "Dialog.BtnOk")
    Swag.assert(evt.updatedFields.has(.Disabled))
    Swag.assert(evt.updatedFields.has(.Name))
    Swag.assert(not evt.updatedFields.has(.Shortcut))
    Swag.assert(evt.renderingHint.has(.ExclusiveGroup))
    Swag.assert(evt.disabled)
    Swag.assert(evt.name == "Ok")
}

// A mouse event keeps its kind, position, motion, and modifiers.
#test
{
    var mouseEvt: MouseEvent
    mouseEvt.kind       = .Move
    mouseEvt.surfacePos = {10, 20}
    mouseEvt.delta      = {-3, 4}
    mouseEvt.modifiers  = Input.KeyModifiers.Control | .Shift

    Swag.assert(mouseEvt.kind == .Move)
    Swag.assert(mouseEvt.surfacePos == Math.Point{10, 20})
    Swag.assert(mouseEvt.delta == Math.Point{-3, 4})
    Swag.assert(mouseEvt.modifiers == .CtrlShift)
}

// Heap command, resize, and move events report their dynamic type and keep their payload.
#test
{
    let cmd = Event.create'CommandEvent()
    defer Memory.delete(cmd)
    cmd.id = Dialog.BtnCancel
    Swag.assert(Swag.kindOf(cast(IEvent, cmd)) == #typeof(CommandEvent))
    Swag.assert(cmd.id == "Dialog.BtnCancel")
    Swag.assert(cmd.source == null)

    let resize = Event.create'ResizeEvent()
    defer Memory.delete(resize)
    resize.oldSize = {640, 480}
    Swag.assert(Swag.kindOf(cast(IEvent, resize)) == #typeof(ResizeEvent))
    Swag.assert(resize.oldSize == Math.Point{640, 480})

    let move = Event.create'MoveEvent()
    defer Memory.delete(move)
    move.oldPos = {12, 34}
    Swag.assert(Swag.kindOf(cast(IEvent, move)) == #typeof(MoveEvent))
    Swag.assert(move.oldPos == Math.Point{12, 34})
}

// Paint, focus, state, and notification events start from their defaults and keep the kind they are given.
#test
{
    var paint: PaintEvent
    Swag.assert(paint.kind == .Content)

    var focus: FocusEvent
    Swag.assert(focus.canChangeFocus)
    focus.kind = .CanLose
    focus.canChangeFocus = false
    Swag.assert(focus.kind == .CanLose)
    Swag.assert(not focus.canChangeFocus)

    var state: StateEvent
    state.kind = .Hide
    Swag.assert(state.kind == .Hide)

    var notify: NotifyEvent
    notify.kind = .ThemeChanged
    Swag.assert(notify.kind == .ThemeChanged)
}

// Key, system-user, and system-command events keep what their sender wrote.
#test
{
    var key: KeyEvent
    key.kind      = .Character
    key.character = 'x'
    key.modifiers = .Alt
    Swag.assert(key.kind == .Character)
    Swag.assert(key.character == 'x')
    Swag.assert(key.modifiers == .Alt)

    var sysUser: SysUserEvent
    sysUser.kind      = .CustomMessage
    sysUser.messageId = 42
    sysUser.param     = 22
    Swag.assert(sysUser.kind == .CustomMessage)
    Swag.assert(sysUser.messageId == 42)
    Swag.assert(sysUser.param == 22)

    sysUser.kind       = .TrayIcon
    sysUser.trayAction = .ContextMenu
    Swag.assert(sysUser.trayAction == .ContextMenu)

    var sysCommand: SysCommandEvent
    sysCommand.kind = .Restore
    Swag.assert(sysCommand.kind == .Restore)
}
