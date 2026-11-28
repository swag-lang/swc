#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Presenters refresh semantic state even when the glyph and command id stay unchanged.
#test
{
    var destructive = true
    var host: Testing.HeadlessHost
    host.setup(360, 240)
    let button = IconButton.create(&host.root, host.theme.icon(.Remove), id: "remove")
    var state  = Testing.commandState("remove")
    state.updatedFields = .RenderingHint | .Icon
    state.icon = host.theme.icon(.Remove)
    state.renderingHint = .Critical
    button.button.IWnd.onApplyStateEvent(&state)
    Swag.require(button.critical)
    let push = PushButton.create(&host.root, "Remove", id: "remove", form: .Default)
    push.button.IWnd.onApplyStateEvent(&state)
    Swag.require(push.paintedForm() == .Destructive)
    push.setIconSize(16, 16)
    push.fitWidthToLabel()
    let compactWidth = push.position.width
    push.setIconSize(32, 32)
    push.fitWidthToLabel()
    Swag.require(push.position.width == compactWidth + 16)

    state.renderingHint = .None
    state.icon.color    = host.theme.colors.arc
    button.button.IWnd.onApplyStateEvent(&state)
    Swag.require(not button.critical and button.icon.color == host.theme.colors.arc)

    host.root.hookOnEvent = func|destructive = &destructive|(_, event)->bool
    {
        if event is CommandStateEvent as state where state.kind == .Compute
        {
            state.updatedFields |= .RenderingHint
            state.renderingHint = destructive[] ? .Critical : .None
            return true
        }

        return false
    }

    let menu = MenuCtrl.createPopup(&host.root, owner: &host.root)
    let item = menu.addItem("Remove", "remove")
    menu.updateState()
    Swag.require(item.critical)
    destructive = false
    menu.updateState()
    Swag.require(not item.critical)
}
