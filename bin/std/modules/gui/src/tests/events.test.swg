#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag, Core

#test
{
    let evt = Event.create'CommandStateEvent()
    @assert(evt.type == #typeof(CommandStateEvent))
    @assert(!evt.accepted)

    evt.kind = CommandStateEvent.Kind.ApplyCommandState
    evt.id = Dialog.BtnOk
    evt.setFlags = CommandStateEvent.SetFlags.Disabled | CommandStateEvent.SetFlags.Name
    evt.renderingHint = CommandStateEvent.RenderingHint.ExclusiveGroup
    evt.disabled = true
    evt.name = "Ok"

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
    mouseEvt.kind = .MouseMove
    mouseEvt.surfacePos = {10, 20}
    mouseEvt.move = {-3, 4}
    mouseEvt.modifiers = Input.KeyModifiers.Control | Input.KeyModifiers.Shift

    @assert(mouseEvt.kind == MouseEvent.Kind.MouseMove)
    @assert(mouseEvt.surfacePos == Math.Point{10, 20})
    @assert(mouseEvt.move == Math.Point{-3, 4})
    @assert(mouseEvt.modifiers == Input.KeyModifiers.CtrlShift)
}
