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
    Swag.assert(cast(*void) base != cast(*void) evt)
    Swag.assert(cast #try (*OffsetOwnedEvent) base == evt)
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
    Swag.assert(cast #try (*CommandStateEvent) view == evt)
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
    Swag.assert(Swag.kindOf(cast(IEvent) cmd) == #typeof(CommandEvent))
    Swag.assert(cmd.id == "Dialog.BtnCancel")
    Swag.assert(cmd.source == null)

    let resize = Event.create'ResizeEvent()
    defer Memory.delete(resize)
    resize.oldSize = {640, 480}
    Swag.assert(Swag.kindOf(cast(IEvent) resize) == #typeof(ResizeEvent))
    Swag.assert(resize.oldSize == Math.Point{640, 480})

    let move = Event.create'MoveEvent()
    defer Memory.delete(move)
    move.oldPos = {12, 34}
    Swag.assert(Swag.kindOf(cast(IEvent) move) == #typeof(MoveEvent))
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
