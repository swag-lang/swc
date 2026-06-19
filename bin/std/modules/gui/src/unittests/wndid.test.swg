#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag, Core

struct GuiWndIdTestScope
{
    newCmdId("Run")
    newCmdId("Cancel")
}

#test
{
    @assert(GuiWndIdTestScope.Run == "GuiWndIdTestScope.Run")
    @assert(GuiWndIdTestScope.Cancel == "GuiWndIdTestScope.Cancel")
    @assert(Dialog.BtnOk == "Dialog.BtnOk")
    @assert(Dialog.BtnCancel == "Dialog.BtnCancel")
}
