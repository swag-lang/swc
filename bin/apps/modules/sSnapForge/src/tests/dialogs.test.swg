#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// The caption appearance action reaches the standard application about dialog and closes it
// through the normal modal action.
#test
{
    var gui: Gui.Testing.HeadlessHost
    defer g_Main = null
    gui.setup(900, 700)
    defer gui.shutdown()
    gui.bindApplication(&g_App)

    let main = MainWnd.create(&gui.root)
    g_Main = main

    @assert(!main.appearanceButton.sigAboutRequested.isEmpty())
    gui.clickModalButtonWhenShown(Dialog.BtnCancel)
    @assert(Gui.Testing.actionExecute'ActionAbout(main, ActionAbout.About))
    gui.pump()
    @assert(gui.autoHandled)
    @assert(gui.openedSurfaceCount() == 0)
}
