using Core, Pixel

// Displays application identity, title, descriptive rich text, and optional icons.
public struct AboutDlg
{
    using dialog: Dialog     // Embedded dialog state.
    readonly
    {
        #[Swag.Late]
        {
            labelIcon:         *Label     // Optional large application icon.
            labelMessageTitle: *Label     // Prominent application or product title.
            labelMessage:      *Label     // Rich descriptive message.
        }
    }
}

// Configures the content and icons of an [[Gui.AboutDlg]].
public struct AboutDlgParams
{
    surfaceTitle: string     // Native surface title.
    contentTitle: string     // Prominent application or product title.
    message:      string     // Rich descriptive text.
    surfaceIcon:  Icon       // Optional title-bar icon.
    contentIcon:  Icon       // Optional large content icon.
}

public impl AboutDlg
{
    // Creates an about dialog; zero dimensions use the standard 500 by 300 size.
    #[Swag.Discardable]
    func create(from: *Surface, params: AboutDlgParams, width, height: s32 = 0)->*AboutDlg
    {
        Debug.assert(from != null)
        Debug.assert(width >= 0 and height >= 0, "dialog dimensions cannot be negative")
        let dlg = Wnd.create'AboutDlg()
        let w   = width != 0 ? cast(s32) width : 500
        let h   = height != 0 ? cast(s32) height : 300
        let srf = dlg.createSurface(from, 0, 0, w, h, .CloseButton)
        srf.setTitle(params.surfaceTitle)
        srf.center(from)

        with let stackLayout = StackLayoutCtrl.create(srf.view())
        {
            .dockStyle = .Center
            .padding.y = params.contentIcon.sizeY * 0.25
        }

        with dlg.labelMessageTitle = Label.create(stackLayout, params.contentTitle)
        {
            let fontSize = cast(s32) (dlg.themeMetrics().defaultFontSize * 1.5)
            .style.setFont(dlg.theme().createDefaultFontfamily(fontSize))
            .dockStyle = .Top
            .setTextAlignment(.Left, .Top)
            .updateFlags(.AutoHeight)
        }

        with dlg.labelMessage = Label.create(stackLayout, params.message, flags: .AutoHeight | .WordWrap)
        {
            .dockStyle = .Top
            .setTextAlignment(.Left, .Top)
        }

        if params.surfaceIcon.isValid()
        {
            var cpyIcon = params.surfaceIcon
            cpyIcon.sizeX, cpyIcon.sizeY = dlg.themeMetrics().wnd_BigCaptionCY * 0.7
            srf.setIcon(cpyIcon)
        }

        if params.contentIcon.isValid()
        {
            let widthIconPanel = params.contentIcon.sizeX + params.contentIcon.sizeX * 0.5
            with dlg.labelIcon = Label.create(srf.wnd.view, "", {0, 0, widthIconPanel, 0})
            {
                .dockStyle = .Left
                .padding.y = params.contentIcon.sizeY * 0.25
                .setIcon(params.contentIcon)
                .setIconAlignment(.Center, .Top)
            }
        }

        dlg.addButton(strings().dlg_Close, Dialog.BtnYes)
        dlg.sendResizeEvent()
        return dlg
    }
}
