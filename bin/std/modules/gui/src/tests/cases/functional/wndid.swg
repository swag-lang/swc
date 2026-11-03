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
    Swag.require(GuiWndIdTestScope.Run == "GuiWndIdTestScope.Run")
    Swag.require(GuiWndIdTestScope.Cancel == "GuiWndIdTestScope.Cancel")
    Swag.require(Dialog.BtnOk == "Dialog.BtnOk")
    Swag.require(Dialog.BtnCancel == "Dialog.BtnCancel")
}
