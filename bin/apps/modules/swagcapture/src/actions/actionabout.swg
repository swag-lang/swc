using Gui

// The command that shows the about box.
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
        let main = mainWndOf(cxt)
        switch cxt.id
        {
        case .About:
            evt.updatedFields |= .Name | .Icon
            evt.name = strings().appearance_About
            evt.icon = main.theme().icon(.About)
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        // Dated and versioned by the compilation of this executable.
        const BuildDate = #run Time.DateTime.now()
        let version = Format.toString("%.%.%", #swcversion, #swcrevision, #swcbuildnum)

        with var about: ApplicationAboutDlgParams
        {
            .productName     = ProductName
            .version         = version
            .buildDate       = BuildDate
            .sourceUrl       = "https://github.com/swag-lang/swc/tree/master/bin/apps/modules/swagcapture"
            .copyrightHolder = "Christophe Beaudet"
        }

        discard AboutDlg.createApplication(mainWndOf(cxt).surface!, about).doModal()
        return true
    }
}
