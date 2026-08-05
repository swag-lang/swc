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

        let metrics = dlg.themeMetrics()
        let pad     = metrics.dialog_Padding

        // One accent rule across the top edge, the same one every standard Swag surface
        // carries. A box that names the product is the last place to drop the family mark.
        Separator.create(srf.view(), .Top, .Accent)

        // The text column keeps the dialog margin on the edges it touches. Its leading edge
        // is the mark's business, so it takes nothing there.
        with let stackLayout = StackLayoutCtrl.create(srf.view())
        {
            .dockStyle = .Center
            .padding   = {0, pad, pad, pad}
        }

        // The product name is the one heading of the box, so it is set once, in bold, and
        // nothing else in here competes with it.
        with dlg.labelMessageTitle = Label.create(stackLayout, params.contentTitle)
        {
            let fontSize = cast(u32) (metrics.defaultFontSize * 1.5)
            .style.setFont(dlg.theme().createDefaultFont(fontSize, .Bold), .Regular)
            .dockStyle = .Top
            .setTextAlignment(.Left, .Top)
            .updateFlags(.AutoHeight)
        }

        with dlg.labelMessage = Label.create(stackLayout, params.message, flags: .AutoHeight | .WordWrap | .SecondaryText)
        {
            .dockStyle = .Top
            .margin.y  = pad * 0.5
            .setTextAlignment(.Left, .Top)
        }

        if params.surfaceIcon.isValid()
        {
            var cpyIcon = params.surfaceIcon
            cpyIcon.sizeX, cpyIcon.sizeY = metrics.wnd_CaptionIconSize
            srf.setIcon(cpyIcon)
        }

        if params.contentIcon.isValid()
        {
            // The mark keeps one dialog margin of clear space on each side and nothing more:
            // a panel wider than the glyph it holds is room taken from what the box has to
            // say. It stands on the first line of the name rather than above it.
            with dlg.labelIcon = Label.create(srf.wnd.view, "", {0, 0, params.contentIcon.sizeX + 2 * pad, 0})
            {
                .dockStyle = .Left
                .padding.y = pad
                .setIcon(params.contentIcon)
                .setIconAlignment(.Center, .Top)
            }
        }

        dlg.addButton(strings().dlg_Close, Dialog.BtnYes, true)
        dlg.sendResizeEvent()
        return dlg
    }
}
