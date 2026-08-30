using Gui

struct ActionAbout {}

impl ActionAbout
{
    newCmdId("About")
}

impl IActionUI for ActionAbout
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main = cast(*MainWnd) cxt.wnd!
        switch cxt.id
        {
        case .About:
            evt.updatedFields |= .Name | .Icon
            evt.name          = strings().appearance_About
            evt.icon          = main.theme().icon(.About)
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main = cast(*MainWnd) cxt.wnd!
        let view = main.editWnd.editView

        const BuildDate = #run Time.DateTime.now()
        let version = Format.toString("%.%.%", #swcversion, #swcrevision, #swcbuildnum)
        let dlg     = AboutDlg.createApplication(view.surface!, {
            productName: ProductName,
            version: version.toString(),
            buildDate: BuildDate,
            sourceUrl: "https://github.com/swag-lang/swc/tree/master/bin/apps/modules/swagcapture",
            copyrightHolder: "Christophe Beaudet"})

        discard dlg.doModal()

        return true
    }
}
