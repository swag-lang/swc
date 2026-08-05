using Gui

struct ActionOptions {}

impl ActionOptions
{
    newCmdId("Options")
}

impl IActionUI for ActionOptions
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main = cast(*MainWnd) cxt.wnd!

        switch cxt.id
        {
        case .Options:
            evt.updatedFields |= .Name | .Icon
            evt.name          = appStrings().act_Options
            evt.icon          = main.theme().icon(.Options)
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main = cast(*MainWnd) cxt.wnd!
        let view = main.editWnd.editView

        let dlg = Dialog.create(view.surface!, 800, 600, title: appStrings().dlg_TitleOptions, flags: .Border | .CloseButton | .Resizable)
        dlg.addButton(Gui.strings().dlg_Close, Dialog.BtnCancel, true)

        let opt = PropertiesCtrl.create(dlg.view(), flags: .SectionTabs | .SearchBar)
        opt.setAllMargins(10)
        opt.dockStyle = .Center
        opt.addStruct(main.captureOptions, appStrings().ui_MenuCapture)
        opt.addStruct(main.editorOptions, appStrings().ui_SectionEditor)
        opt.addStruct(main.app().options, appStrings().ui_SectionApplication)

        opt.properties.sigValueChanged += func|main|(opt, item)
        {
            main.setTheme()
            main.setLanguage()
            main.setToolRailWidth()
            main.invalidate()
        }

        discard dlg.doModal()
        return true
    }
}
