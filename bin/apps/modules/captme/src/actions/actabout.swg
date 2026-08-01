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
        let main = cast(*MainWnd) notnull cxt.wnd
        switch cxt.id
        {
        case .About:
            evt.updatedFields |= .Name | .Icon
            evt.name     = "About..."
            evt.icon     = main.theme().icon24(.About)
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main = cast(*MainWnd) notnull cxt.wnd
        let view = main.editWnd.editView

        const Date = #run Time.DateTime.now()

        var params: AboutDlgParams = undefined
        params.surfaceTitle = "About CaptMe"
        params.contentTitle = Format.toString("CaptMe %.%.%", #swcversion, #swcrevision, #swcbuildnum).toString()

        var msg: String
        msg            += Format.toString("Build on %{j}", Date)
        msg            += "\n\n"
        msg            += "<b>CaptMe</b> is open source and coded in <url>Swag</url>. You can find the code <url>here</url>."
        msg            += "\n\n"
        msg            += Format.toString("Copyright \u00A9 % Christophe Beaudet", Date.year)
        params.message = msg.toString()

        params.surfaceIcon                               = Icon.from(&main.icons48, 11)
        params.contentIcon                               = Icon.from(&main.appIcon, 0)
        params.contentIcon.sizeX, params.contentIcon.sizeY = 96
        params.contentIcon.color                         = Argb.White

        let dlg = AboutDlg.create(notnull view.surface, params, height: 330)
        dlg.labelMessage.sigLinkActivated += func(lbl, txt)
        {
            switch txt
            {
            case "Swag": Env.openUrl("https://www.swag-lang.org/")
            case "here": Env.openUrl("https://github.com/swag-lang/swag/tree/master/bin/apps/modules/captme/")
            }
        }

        discard dlg.doModal()

        return true
    }
}
