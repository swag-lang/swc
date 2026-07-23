#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core

#test
{
    let evt = Event.create'CommandStateEvent()
    @assert(evt.type == #typeof(CommandStateEvent))
    @assert(!evt.accepted)

    evt.kind          = CommandStateEvent.Kind.ApplyCommandState
    evt.id            = Dialog.BtnOk
    evt.setFlags      = CommandStateEvent.SetFlags.Disabled | CommandStateEvent.SetFlags.Name
    evt.renderingHint = CommandStateEvent.RenderingHint.ExclusiveGroup
    evt.disabled      = true
    evt.name          = "Ok"

    @assert(evt.kind == CommandStateEvent.Kind.ApplyCommandState)
    @assert(evt.id == "Dialog.BtnOk")
    @assert(evt.setFlags.has(CommandStateEvent.SetFlags.Disabled))
    @assert(evt.setFlags.has(CommandStateEvent.SetFlags.Name))
    @assert(!evt.setFlags.has(CommandStateEvent.SetFlags.Shortcut))
    @assert(evt.renderingHint.has(CommandStateEvent.RenderingHint.ExclusiveGroup))
    @assert(evt.disabled)
    @assert(evt.name == "Ok")

    Memory.delete(evt)
}

#test
{
    var mouseEvt: MouseEvent
    mouseEvt.kind       = .MouseMove
    mouseEvt.surfacePos = {10, 20}
    mouseEvt.move       = {-3, 4}
    mouseEvt.modifiers  = Input.KeyModifiers.Control | Input.KeyModifiers.Shift

    @assert(mouseEvt.kind == MouseEvent.Kind.MouseMove)
    @assert(mouseEvt.surfacePos == Math.Point{10, 20})
    @assert(mouseEvt.move == Math.Point{-3, 4})
    @assert(mouseEvt.modifiers == Input.KeyModifiers.CtrlShift)
}

#test
{
    let cmd = Event.create'CommandEvent()
    cmd.id = Dialog.BtnCancel
    @assert(cmd.type == #typeof(CommandEvent))
    @assert(cmd.id == "Dialog.BtnCancel")
    @assert(cmd.source == null)
    Memory.delete(cmd)

    let resize = Event.create'ResizeEvent()
    resize.oldSize = {640, 480}
    @assert(resize.type == #typeof(ResizeEvent))
    @assert(resize.oldSize == Math.Point{640, 480})
    Memory.delete(resize)

    let move = Event.create'MoveEvent()
    move.oldPos = {12, 34}
    @assert(move.type == #typeof(MoveEvent))
    @assert(move.oldPos == Math.Point{12, 34})
    Memory.delete(move)
}

#test
{
    var paint: PaintEvent
    @assert(paint.kind == PaintEvent.Kind.Paint)

    var focus: FocusEvent
    @assert(focus.canChangeFocus)
    focus.kind           = .CanKillFocus
    focus.canChangeFocus = false
    @assert(focus.kind == FocusEvent.Kind.CanKillFocus)
    @assert(!focus.canChangeFocus)

    var state: StateEvent
    state.kind = .Hide
    @assert(state.kind == StateEvent.Kind.Hide)

    var notify: NotifyEvent
    notify.ntfyKind = .ThemeChanged
    @assert(notify.ntfyKind == NotifyEvent.Kind.ThemeChanged)
}

#test
{
    var key: KeyEvent
    key.kind      = .Rune
    key.char      = 'x'
    key.modifiers = Input.KeyModifiers.Alt
    @assert(key.kind == KeyEvent.Kind.Rune)
    @assert(key.char == 'x')
    @assert(key.modifiers == Input.KeyModifiers.Alt)

    var sysUser: SysUserEvent
    sysUser.userMsg = 42
    sysUser.param0  = 11
    sysUser.param1  = 22
    @assert(sysUser.userMsg == 42)
    @assert(sysUser.param0 == 11)
    @assert(sysUser.param1 == 22)

    var sysCommand: SysCommandEvent
    sysCommand.kind = .Restore
    @assert(sysCommand.kind == SysCommandEvent.Kind.Restore)
}
