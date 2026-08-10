using Core, Pixel

// Displays application identity, title, descriptive rich text, and optional icons.
public struct AboutDlg
{
    public using dialog: Dialog     // Embedded dialog state.
    public readonly
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
    public
    {
        surfaceTitle: string     // Native surface title.
        contentTitle: string     // Prominent application or product title.
        message:      string     // Rich descriptive text.
        surfaceIcon:  Icon       // Optional title-bar icon.
        contentIcon:  Icon       // Optional large content icon.
    }
}

public impl AboutDlg
{
    // Creates an about dialog; a zero width uses 500 units and a zero height fits the content.
    #[Swag.Discardable]
    func create(from: *Surface, params: AboutDlgParams, width, height: s32 = 0)->*AboutDlg
    {
        Debug.assert(from != null)
        Debug.assert(width >= 0 and height >= 0, "dialog dimensions cannot be negative")
        let dlg = Wnd.create'AboutDlg()
        let w   = width != 0 ? cast(s32) width : 500
        let h   = height != 0 ? cast(s32) height : 300
        let srf = dlg.createSurface(from, 0, 0, w, h)
        srf.setTitle(params.surfaceTitle)
        srf.center(from)

        let metrics = dlg.themeMetrics()
        let body    = dlg.createContentView()

        if params.contentIcon.isValid()
        {
            // The product glyph takes one compact column and keeps the same clear lane as a
            // message status icon. The dialog body already owns the outer inset.
            let gap = metrics.dialog_BtnPadding * 2
            with dlg.labelIcon = Label.create(body, "", {0, 0, params.contentIcon.sizeX + gap, 0})
            {
                .dockStyle = .Left
                .setIcon(params.contentIcon)
                .setIconAlignment(.Left, .Center)
            }
        }

        // The name and its description form one centered group: one heading, one measured gap,
        // then the supporting copy. Any remaining room is shared above and below the group.
        let stackLayout = StackLayoutCtrl.create(body, .VerticalCenter)
        with stackLayout
        {
            .dockStyle = .Center
            .spacing   = metrics.dialog_BtnPadding * 2
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
            .setTextAlignment(.Left, .Top)
        }

        if params.surfaceIcon.isValid()
        {
            var cpyIcon = params.surfaceIcon
            cpyIcon.sizeX, cpyIcon.sizeY = metrics.wnd_CaptionIconSize
            srf.setIcon(cpyIcon)
        }

        dlg.addButton(strings().dlg_Close, Dialog.BtnCancel, true)
        dlg.sendResizeEvent()
        if height == 0
        {
            dlg.applyLayout()
            let availableWidth = Math.max(stackLayout.position.width, 1)
            var contentHeight  = stackLayout.measure({availableWidth, 0}).preferred.y
            if params.contentIcon.isValid() do
                contentHeight = Math.max(contentHeight, cast(f32) params.contentIcon.sizeY)
            dlg.fitHeightToContent(contentHeight)
            srf.center(from)
        }
        return dlg
    }
}
