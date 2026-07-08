#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// About is a real modal dialog; the headless modal driver closes it through its
// normal Close button.
#test
{
    var gui: Testing.HeadlessHost
    gui.setup(900, 700)
    gui.bindApplication(&g_App)

    let main = MainWnd.create(&gui.root)
    g_Main = main

    gui.clickModalButtonWhenShown(Dialog.BtnYes)
    @assert(Testing.actionExecute'ActionAbout(main, ActionAbout.About))
    gui.pump()
    @assert(gui.autoHandled)
    @assert(gui.app.surfaces.count == 0)

    gui.shutdown()
    g_Main = null
}
