#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

struct GuiWndIdTestScope
{
    newCmdId("Run")
    newCmdId("Cancel")
}

#test
{
    Swag.assert(GuiWndIdTestScope.Run == "GuiWndIdTestScope.Run")
    Swag.assert(GuiWndIdTestScope.Cancel == "GuiWndIdTestScope.Cancel")
    Swag.assert(Dialog.BtnOk == "Dialog.BtnOk")
    Swag.assert(Dialog.BtnCancel == "Dialog.BtnCancel")
}
