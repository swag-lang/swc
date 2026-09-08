#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// The caption appearance action reaches the standard application about dialog and closes it
// through the normal modal action.
#test
{
    var gui: Gui.Testing.HeadlessHost
    gui.setup(1024, 640)
    gui.bindApplication(&g_App)
    registerAppStrings(&g_App.resources)
    registerAppStrings(&gui.app.resources)

    let main = MainWnd.create(&gui.surfaceWnd)
    main.setPosition(gui.surfaceWnd.paddedClientRect())
    main.applyLayout()
    defer
    {
        main.libWnd.requestClose()
        gui.shutdown()
        g_Main = null
    }

    Swag.assert(main.surface == &gui.surface and main.editWnd.editView.surface == &gui.surface)
    Swag.assert(!main.appearanceButton.sigAboutRequested.isEmpty())
    gui.clickModalButtonWhenShown(Dialog.BtnCancel)
    let actionExecuted = Gui.Testing.actionExecute'ActionAbout(main, ActionAbout.About)
    Swag.assert(actionExecuted)
    gui.pump()
    Swag.assert(gui.autoHandled)
    Swag.assert(gui.openedSurfaceCount() == 0)
}
