#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

#test
{
    let evt = Event.create'CommandStateEvent()
    Swag.assert(evt.type == #typeof(CommandStateEvent))
    Swag.assert(!evt.accepted)

    evt.kind          = CommandStateEvent.Kind.Apply
    evt.id            = Dialog.BtnOk
    evt.updatedFields = CommandStateEvent.UpdatedFields.Disabled | CommandStateEvent.UpdatedFields.Name
    evt.renderingHint = CommandStateEvent.RenderingHint.ExclusiveGroup
    evt.disabled      = true
    evt.name          = "Ok"

    Swag.assert(evt.kind == CommandStateEvent.Kind.Apply)
    Swag.assert(evt.id == "Dialog.BtnOk")
    Swag.assert(evt.updatedFields.has(CommandStateEvent.UpdatedFields.Disabled))
    Swag.assert(evt.updatedFields.has(CommandStateEvent.UpdatedFields.Name))
    Swag.assert(!evt.updatedFields.has(CommandStateEvent.UpdatedFields.Shortcut))
    Swag.assert(evt.renderingHint.has(CommandStateEvent.RenderingHint.ExclusiveGroup))
    Swag.assert(evt.disabled)
    Swag.assert(evt.name == "Ok")

    Memory.delete(evt)
}

#test
{
    var mouseEvt: MouseEvent
    mouseEvt.kind       = .Move
    mouseEvt.surfacePos = {10, 20}
    mouseEvt.delta      = {-3, 4}
    mouseEvt.modifiers  = Input.KeyModifiers.Control | Input.KeyModifiers.Shift

    Swag.assert(mouseEvt.kind == MouseEvent.Kind.Move)
    Swag.assert(mouseEvt.surfacePos == Math.Point{10, 20})
    Swag.assert(mouseEvt.delta == Math.Point{-3, 4})
    Swag.assert(mouseEvt.modifiers == Input.KeyModifiers.CtrlShift)
}

#test
{
    let cmd = Event.create'CommandEvent()
    cmd.id = Dialog.BtnCancel
    Swag.assert(cmd.type == #typeof(CommandEvent))
    Swag.assert(cmd.id == "Dialog.BtnCancel")
    Swag.assert(cmd.source == null)
    Memory.delete(cmd)

    let resize = Event.create'ResizeEvent()
    resize.oldSize = {640, 480}
    Swag.assert(resize.type == #typeof(ResizeEvent))
    Swag.assert(resize.oldSize == Math.Point{640, 480})
    Memory.delete(resize)

    let move = Event.create'MoveEvent()
    move.oldPos = {12, 34}
    Swag.assert(move.type == #typeof(MoveEvent))
    Swag.assert(move.oldPos == Math.Point{12, 34})
    Memory.delete(move)
}

#test
{
    var paint: PaintEvent
    Swag.assert(paint.kind == PaintEvent.Kind.Content)

    var focus: FocusEvent
    Swag.assert(focus.canChangeFocus)
    focus.kind           = .CanLose
    focus.canChangeFocus = false
    Swag.assert(focus.kind == FocusEvent.Kind.CanLose)
    Swag.assert(!focus.canChangeFocus)

    var state: StateEvent
    state.kind = .Hide
    Swag.assert(state.kind == StateEvent.Kind.Hide)

    var notify: NotifyEvent
    notify.kind = .ThemeChanged
    Swag.assert(notify.kind == NotifyEvent.Kind.ThemeChanged)
}

#test
{
    var key: KeyEvent
    key.kind      = .Character
    key.character = 'x'
    key.modifiers = Input.KeyModifiers.Alt
    Swag.assert(key.kind == KeyEvent.Kind.Character)
    Swag.assert(key.character == 'x')
    Swag.assert(key.modifiers == Input.KeyModifiers.Alt)

    var sysUser: SysUserEvent
    sysUser.kind      = .CustomMessage
    sysUser.messageId = 42
    sysUser.param     = 22
    Swag.assert(sysUser.kind == SysUserEvent.Kind.CustomMessage)
    Swag.assert(sysUser.messageId == 42)
    Swag.assert(sysUser.param == 22)

    sysUser.kind       = .TrayIcon
    sysUser.trayAction = .ContextMenu
    Swag.assert(sysUser.trayAction == SysUserEvent.TrayAction.ContextMenu)

    var sysCommand: SysCommandEvent
    sysCommand.kind = .Restore
    Swag.assert(sysCommand.kind == SysCommandEvent.Kind.Restore)
}
