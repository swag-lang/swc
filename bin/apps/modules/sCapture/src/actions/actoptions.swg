using Gui

struct ActionOptions {}

// Fills the options grid with the three reflected sections, in display order.
//
// Called again after a language switch: the rows resolve their wording as they are built.
private func fillOptions(opt: *PropertiesCtrl, main: *MainWnd)
{
    opt.addStruct(main.captureOptions, appStrings().ui_MenuCapture)
    opt.addStruct(main.editorOptions, appStrings().ui_SectionEditor)
    opt.addStruct(main.app().options, appStrings().ui_SectionApplication)
}

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
        fillOptions(opt, main)

        opt.properties.sigValueChanged += func|main, opt|(prop, item)
        {
            let wasLanguage = String.from(Gui.activeLanguage())
            main.setTheme()
            main.setLanguage()
            main.setToolRailWidth()

            // Every row here is generated from an attribute literal resolved at build time,
            // and the section tabs carry their captions the same way, so the language the
            // reader just picked only reaches this dialog by building it again.
            if wasLanguage != Gui.activeLanguage()
            {
                opt.clear()
                fillOptions(opt, main)
                opt.surface!.setTitle(appStrings().dlg_TitleOptions)
                opt.applyLayout()
            }

            main.invalidate()
        }

        discard dlg.doModal()
        return true
    }
}
