using Core, Pixel

// Displays application identity, title, descriptive rich text, and optional icons.
public struct AboutDlg
{
    public
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

    sourceUrl: String     // Source page owned for the lifetime of an application about dialog.
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

// Configures the standard identity and provenance shown for an application.
public struct ApplicationAboutDlgParams
{
    public
    {
        productName:     string            // Product name used by the surface and content heading.
        version:         string            // Version appended to the product heading.
        buildDate:       Time.DateTime     // Build date reported in the first paragraph.
        sourceUrl:       string            // Source page opened by the source link.
        copyrightHolder: string            // Holder named after the build year.
    }
}

public impl AboutDlg
{
    // Creates the standard application about dialog from product identity and provenance.
    //
    // The application icon supplies both marks. The dialog owns the source URL until it closes
    // and opens it from the second link; the first link opens the Swag website.
    #[Swag.Discardable]
    func createApplication(from: *Surface, params: ApplicationAboutDlgParams)->*AboutDlg
    {
        let texts = strings()

        var message: String
        message += Format.toString(texts.about_Build, params.buildDate)
        message += "\n\n"
        message += Format.toString(texts.about_Source, params.productName)
        message += "\n\n"
        message += Format.toString(texts.about_Copyright, params.buildDate.year, params.copyrightHolder)

        let app     = from.app
        let metrics = app.theme.metrics
        let colors  = app.theme.colors
        let title   = Format.toString("% %", params.productName, params.version)
        let dlg     = create(from, {
            surfaceTitle: params.productName,
            contentTitle: title.toString(),
            message: message.toString(),
            surfaceIcon: app.appIconAt(metrics.wnd_CaptionIconSize, colors.wnd_CaptionBk),
            contentIcon: app.appIconAt(64, colors.dlg_Bk)})
        dlg.sourceUrl = String.from(params.sourceUrl)
        dlg.labelMessage.sigLinkActivated += func|dlg|(label, text)
        {
            discard label
            if text == "Swag" do
                Env.openUrl("https://www.swag-lang.org/")
            elif !dlg.sourceUrl.isEmpty() do
                Env.openUrl(dlg.sourceUrl.toString())
        }

        return dlg
    }

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
