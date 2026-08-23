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

    #[Swag.Late]
    {
        identityView:   *Wnd           // Raised product block carrying the mark and heading.
        identityAccent: *Separator     // Single Swag accent anchoring that product block.
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
            contentIcon: app.appIconAt(64, colors.view_Bk)})
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

        // Identity and provenance are two quiet tiers: the product owns one raised panel and one
        // accent, while the supporting copy remains on the dialog surface below it.
        let stackLayout = StackLayoutCtrl.create(body, .VerticalCenter)
        with stackLayout
        {
            .dockStyle = .Center
            .spacing   = metrics.dialog_BtnPadding * 2
        }

        // VerticalCenter preserves each child's authored cross-axis extent. Resolve the body now
        // so the plain identity window can author the exact width it must keep.
        dlg.applyLayout()

        let identityInset = metrics.dialog_Padding
        with dlg.identityView = Wnd.create'Wnd(stackLayout, {0, 0, stackLayout.position.width, 0})
        {
            .backgroundStyle = .View
        }

        dlg.identityAccent = Separator.create(dlg.identityView, .Top, .Accent)
        let identityContent = Wnd.create'Wnd(dlg.identityView)
        identityContent.dockStyle = .Center
        identityContent.padding   = {identityInset, identityInset, identityInset, identityInset}

        if params.contentIcon.isValid()
        {
            // The mark has a reserved lane, which keeps the heading optically centered in the
            // remaining product block without making the descriptive copy inherit that inset.
            let gap = metrics.dialog_BtnPadding * 2
            with dlg.labelIcon = Label.create(identityContent, "", {0, 0, params.contentIcon.sizeX + gap, 0})
            {
                .dockStyle = .Left
                .setIcon(params.contentIcon)
                .setIconAlignment(.Left, .Center)
            }
        }

        // The product name is the one heading of the box; the accent and mark support it without
        // introducing another caption or a decorative color outside the active theme.
        with dlg.labelMessageTitle = Label.create(identityContent, params.contentTitle)
        {
            let fontSize = cast(u32) (metrics.defaultFontSize * 1.5)
            .style.setFont(dlg.theme().createDefaultFont(fontSize, .Bold), .Regular)
            .dockStyle = .Center
            .setTextAlignment(.Left, .Center)
            .updateFlags(.AutoHeight)
        }

        let titleHeight    = dlg.labelMessageTitle.measure({w, 0}).preferred.y
        var identityHeight = titleHeight
        if params.contentIcon.isValid() do
            identityHeight = Math.max(identityHeight, cast(f32) params.contentIcon.sizeY)
        dlg.identityView.position.height = identityHeight + 2 * identityInset + dlg.identityAccent.position.height

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
        dlg.buttonBar.applyLayout()
        dlg.applyLayout()
        if height == 0
        {
            let availableWidth = Math.max(stackLayout.position.width, 1)
            let contentHeight  = stackLayout.measure({availableWidth, 0}).preferred.y
            dlg.fitHeightToContent(contentHeight)
            srf.center(from)
        }

        return dlg
    }
}
