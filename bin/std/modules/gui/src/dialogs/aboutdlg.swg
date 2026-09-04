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
                #[Swag.Late]
                labelIcon: *Label     // Optional large application icon.
                #[Swag.Late]
                labelMessageTitle: *Label     // Prominent application or product title.
                #[Swag.Late]
                labelMessage: *Label     // Rich descriptive message.
            }
        }
    }

    #[Swag.Late]
    {
        #[Swag.Late]
        identityView: *Wnd     // Raised product block carrying the mark and heading.
        #[Swag.Late]
        identityAccent: *Separator     // Single Swag accent anchoring that product block.
        #[Swag.Late]
        contentStack: *StackLayoutCtrl     // The one column identity, provenance and sections stand in.
    }

    sectionsScroll: #null *ScrollWnd           // Bounded column the added sections stand in.
    sectionsStack:  #null *StackLayoutCtrl     // Stack of headings and paragraphs inside that column.
    fitsToContent:  bool                       // Whether the caller left the height to the content.

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
//
// Anything past that is the application's own and is added with [[Gui.AboutDlg.addSection]].
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

        dlg.contentStack  = stackLayout
        dlg.fitsToContent = height == 0

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
        dlg.fitToContent()
        return dlg
    }

    // Tallest the added sections grow before the column scrolls instead of the box.
    //
    // A list of what an application supports has no natural length, and a box fitted to one is as
    // tall as the display it opens on. Past this the column keeps the box a box.
    const MaxSectionsHeight = 320.0'f32

    // Adds a titled block of application-specific detail under the standard provenance text.
    //
    // This is where an application says what the reader cannot read off its name: the formats it
    // opens, the plugins it carries, what it was built against. `title` names the block and
    // `content` is the rich text under it, wrapped like the rest of the box; either may be empty.
    // The blocks stack in one column and that column scrolls once it reaches
    // [[Gui.AboutDlg.MaxSectionsHeight]], so a long list never makes the box taller than the
    // display it opens on.
    mtd addSection(title, content: string)
    {
        Debug.assert(title.count or content.count, "an about section carries no text")

        let metrics = .themeMetrics()
        if !.sectionsScroll
        {
            // Authored width, like the identity block above it: the column centers its children
            // vertically as a group and leaves the cross axis to each of them.
            with let scroll = Wnd.create'ScrollWnd(.contentStack, "", {0, 0, .contentStack.position.width, 0})
            {
                .padding = 0
                .updateFlags(.DisableHorizontal | .CompactBars | .TransparentBars)
            }

            .sectionsScroll = scroll
            with .sectionsStack = scroll.createView'StackLayoutCtrl()
            {
                .mode    = .Top
                .spacing = metrics.dialog_BtnPadding
            }
        }

        let stack = .sectionsStack!
        if title.count
        {
            // The heading is set through the rich-text marker rather than through a face of its
            // own, so it stays the family the theme gives the box and moves with it.
            var heading = Format.toString("<b>%</b>", title)
            let label   = Label.create(stack, heading.toString(), flags: .AutoHeight | .WordWrap)
            label.setTextAlignment(.Left, .Top)
        }

        if content.count
        {
            let label = Label.create(stack, content, flags: .AutoHeight | .WordWrap | .SecondaryText)
            label.setTextAlignment(.Left, .Top)
        }

        .fitToContent()
    }

    // Gives the sections column the room it asks for, up to the measure, then fits the box.
    private mtd fitToContent()
    {
        let stack = .contentStack!
        .applyLayout()

        let scroll = .sectionsScroll
        if scroll
        {
            // Measured against the width left once a bar is there, whether or not one is showing:
            // measured against the full viewport, the text would wrap one line further the moment
            // the bar appeared, and the column would need the room it was just told it had.
            let inner = .sectionsStack!
            let bar   = .themeMetrics().scrollBar_SmallSize
            let room  = Math.max(scroll.paddedClientRect().width - bar, 1)

            // The column's own content, not its measured size: a scroll view resizes its view to
            // the viewport, and a resized window answers for the size it was given. Rounded out,
            // because the window it goes in lands on whole units: a viewport a fraction shorter
            // than its content shows a scroll bar over a list that fits.
            let needed = Math.ceil(inner.itf.measureContent({room, 0}).y)
            scroll.position.height = Math.min(needed, MaxSectionsHeight)
            scroll.setScrollSize(0, needed)
            .applyLayout()

            // A viewport is not the window around it. Commit the height, then ask what the column
            // really got and add the difference back, so a list that fits shows no scroll bar.
            let chrome = scroll.position.height - scroll.paddedClientRect().height
            if chrome > 0
            {
                scroll.position.height = Math.min(needed + chrome, MaxSectionsHeight)
                .applyLayout()
            }
        }

        if !.fitsToContent do
            return

        let availableWidth = Math.max(stack.position.width, 1)
        let contentHeight  = stack.measure({availableWidth, 0}).preferred.y
        .fitHeightToContent(contentHeight)
        if .parentSurface do
            .surface!.center(.parentSurface!)
    }
}
