#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag, Core

const GuiHeadlessSmoke_CloseWindow = "GuiHeadlessSmoke.CloseWindow"

#test
{
    var host: GuiHeadlessHost
    host.setup(240, 120)
    host.closeOnCommand(GuiHeadlessSmoke_CloseWindow)

    let button = PushButton.create(&host.root, "Close", {20, 20, 90, 30}, GuiHeadlessSmoke_CloseWindow)

    @assert(!host.closed)
    @assert(host.wndAt({40, 30}) == button)

    host.click({40, 30})

    @assert(host.closed)
    @assert(host.commandCount == 1)
    @assert(host.lastCommand == GuiHeadlessSmoke_CloseWindow)
    @assert(host.root.isPendingDestroy)
    @assert(host.root.wndFlags.has(.Hidden))
    @assert(host.app.mouseCaptureWnd == null)
}
