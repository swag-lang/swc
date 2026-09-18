#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A scope whose command identifiers are qualified by its own name.
struct GuiWndIdTestScope
{
    newCmdId("Run")
    newCmdId("Cancel")
}

// A command identifier is its qualified name, whether a test scope or the module declares it.
#test
{
    Swag.assert(GuiWndIdTestScope.Run == "GuiWndIdTestScope.Run")
    Swag.assert(GuiWndIdTestScope.Cancel == "GuiWndIdTestScope.Cancel")
    Swag.assert(Dialog.BtnOk == "Dialog.BtnOk")
    Swag.assert(Dialog.BtnCancel == "Dialog.BtnCancel")
}
