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
            evt.name          = appStrings().act_About
            evt.icon          = main.theme().icon(.About)
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main = cast(*MainWnd) cxt.wnd!
        let view = main.editWnd.editView

        const Date = #run Time.DateTime.now()

        let texts = appStrings()

        var params: AboutDlgParams = undefined
        params.surfaceTitle = "sSnapForge"
        params.contentTitle = Format.toString("sSnapForge %.%.%", #swcversion, #swcrevision, #swcbuildnum).toString()

        // Three short paragraphs, in this order: when it was built, what it is made of, who
        // holds it. Anything a reader would not act on stays out of the box.
        var msg: String
        msg            += Format.toString(texts.msg_AboutBuild, Date)
        msg            += "\n\n"
        msg            += texts.msg_AboutSource
        msg            += "\n\n"
        msg            += Format.toString(texts.msg_AboutCopyright, Date.year)
        params.message = msg.toString()

        params.surfaceIcon       = Icon.from(&main.appIcon, 0)
        params.surfaceIcon.color = Argb.White
        params.contentIcon       = Icon.from(&main.appIcon, 0)
        params.contentIcon.sizeX, params.contentIcon.sizeY = 64
        params.contentIcon.color = Argb.White

        let dlg = AboutDlg.create(view.surface!, params, height: 300)
        dlg.labelMessage.sigLinkActivated += func(lbl, txt)
        {
            switch txt
            {
            case "Swag":        Env.openUrl("https://www.swag-lang.org/")
            case "here", "ici": Env.openUrl("https://github.com/swag-lang/swag/tree/master/bin/apps/sSnapForge/modules/sSnapForge/")
            }
        }

        discard dlg.doModal()

        return true
    }
}
