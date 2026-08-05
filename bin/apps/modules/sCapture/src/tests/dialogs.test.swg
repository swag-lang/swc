#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// About is a real modal dialog; the headless modal driver closes it through its
// normal Close button.
#test
{
    var gui: Gui.Testing.HeadlessHost
    defer g_Main = null
    gui.setup(900, 700)
    defer gui.shutdown()
    gui.bindApplication(&g_App)

    let main = MainWnd.create(&gui.root)
    g_Main = main

    // 'AboutDlg' offers one button, its Close, which carries the cancel identifier.
    gui.clickModalButtonWhenShown(Dialog.BtnCancel)
    @assert(Gui.Testing.actionExecute'ActionAbout(main, ActionAbout.About))
    gui.pump()
    @assert(gui.autoHandled)
    @assert(gui.openedSurfaceCount() == 0)
}
