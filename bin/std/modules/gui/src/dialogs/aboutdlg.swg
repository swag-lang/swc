using Core, Pixel

// Displays the identity of an application: its tile, its name, a mono line of version and date,
// descriptive rich text with its links, and optional sections.
//
// The box has no title line: the name beside the tile is what names it. One Close ends it.
public struct AboutDlg
{
    public
    {
        using dialog: Dialog     // Embedded dialog state.

        readonly
        {
            late
            {
                labelIcon:         *Label     // Application tile, set only when the parameters carry one.
                labelMessageTitle: *Label     // Product name beside the tile.
                labelIdentity:     *Label     // Mono faint line of version and date under the name; empty when there is none.
                labelMessage:      *Label     // Rich descriptive message.
            }
        }
    }

    late
    {
        identityView: *Wnd     // Header holding the tile, the name and the identity line.
        contentStack: *StackLayoutCtrl     // The one column the header, the message and the sections stand in.
    }

    sectionsScroll: *ScrollWnd?           // Bounded column the added sections stand in.
    sectionsStack:  *StackLayoutCtrl?     // Stack of headings and paragraphs inside that column.
    fitsToContent:  bool                  // Whether the caller left the height to the content.

    sourceUrl: String     // Source page owned for the lifetime of an application about dialog.
}

// Configures the content and icons of an [[Gui.AboutDlg]].
public struct AboutDlgParams
{
    public
    {
        surfaceTitle: string          // Native surface title.
        contentTitle: string          // Product name beside the tile.
        message:      string          // Rich descriptive text.
        surfaceIcon:  Icon            // Optional glyph of the native surface, drawn in the chrome's ink.
        contentIcon:  Icon            // Optional application tile.
        identity:     string = ""     // Optional mono line under the name: a version, a date.
    }
}

// Configures the standard identity and provenance shown for an application.
//
// Anything past that is the application's own and is added with [[Gui.AboutDlg.addSection]].
public struct ApplicationAboutDlgParams
{
    public
    {
        productName:     string            // Product name beside the tile.
        version:         string            // Version, set in mono under the name.
        buildDate:       Time.DateTime     // Build date, set in mono after the version.
        sourceUrl:       string            // Source page opened by the source link.
        copyrightHolder: string            // Holder named after the build year.
    }
}

public impl AboutDlg
{
    // Creates the standard application about dialog from product identity and provenance.
    //
    // The application icon supplies the tile. The dialog owns the source URL until it closes and
    // opens it from the second link; the first link opens the Swag website.
    #[Swag.Discardable]
    func createApplication(from: *Surface, params: ApplicationAboutDlgParams)->*AboutDlg
    {
        let texts = strings()

        var message: String
        message += Format.toString(texts.about_Source, params.productName)
        message += "\n"
        message += Format.toString(texts.about_Copyright, params.buildDate.year, params.copyrightHolder)

        let app      = from.app
        let metrics  = app.theme.metrics
        let colors   = app.theme.colors
        let identity = Format.toString("% · %", params.version, Format.toString(texts.about_Build, params.buildDate))
        let dlg      = create(from, {
            surfaceTitle: params.productName,
            contentTitle: params.productName,
            message: message.toString(),
            surfaceIcon: app.appGlyph(metrics.wnd_CaptionIconSize),
            contentIcon: app.appIconAt(metrics.dialog_TileSize, colors.dlg_Bk),
            identity: identity.toString()})
        dlg.sourceUrl = String.from(params.sourceUrl)
        dlg.labelMessage.focusPolicy      = .Click
        dlg.labelMessage.sigLinkActivated += func|dlg|(_, text)
        {
            if text == "Swag" do
                Env.openUrl("https://www.swag-lang.org/")
            elif not dlg.sourceUrl.isEmpty() do
                Env.openUrl(dlg.sourceUrl.toString())
        }

        return dlg
    }

    // Creates an about dialog; a zero width uses 500 units and a zero height fits the content.
    #[Swag.Discardable]
    func create(from: *Surface, params: AboutDlgParams, width, height: s32 = 0)->*AboutDlg
    {
        Swag.assert(from != null)
        Swag.assert(width >= 0 and height >= 0, "dialog dimensions cannot be negative")
        let dlg = Wnd.create'AboutDlg()
        let w   = width != 0 ? width : 500
        let h   = height != 0 ? height : 300
        let srf = dlg.createSurface(from, 0, 0, w, h)

        // The name beside the tile names the box, so the body has no title line of its own; the
        // surface keeps one for the task switcher.
        srf.setTitle(params.surfaceTitle)
        srf.center(from)

        let metrics = dlg.themeMetrics()
        let gap     = metrics.dialog_BtnPadding * 2
        with let stackLayout = StackLayoutCtrl.create(dlg.createContentView(), .Top)
        {
            .dockStyle = .Center
            .spacing   = gap
        }

        dlg.contentStack  = stackLayout
        dlg.fitsToContent = height == 0

        // The stack keeps each child's authored cross-axis extent. Resolve the body now so the
        // header can author the exact width it must keep.
        dlg.applyLayout()

        // The header: the tile, then the name and the mono line of identity beside it, on one
        // left edge. Nothing frames it: the tile is the one block of the box.
        dlg.identityView = Wnd.create'Wnd(stackLayout, Math.Rectangle{0, 0, stackLayout.position.width, 0})

        var headerHeight = 0'f32
        var tileWidth    = 0'f32
        if params.contentIcon.isValid()
        {
            with dlg.labelIcon = Label.create(dlg.identityView, "", Math.Rectangle{0, 0, params.contentIcon.sizeX + gap, 0})
            {
                .dockStyle = .Left
                .setIcon(params.contentIcon)
                .setIconAlignment(.Left, .Center)
            }

            headerHeight = cast(f32, params.contentIcon.sizeY)
            tileWidth    = dlg.labelIcon.position.width
        }

        let names = Wnd.create'Wnd(dlg.identityView)
        names.dockStyle = .Center

        with dlg.labelMessageTitle = Label.create(names, params.contentTitle)
        {
            .style.setFont(dlg.theme().createDefaultFont(metrics.dialog_NameFontSize, .Bold), .Regular)
            .dockStyle = .Top
            .setTextAlignment(.Left, .Top)
            .updateFlags(.AutoHeight)
        }

        with dlg.labelIdentity = Label.create(names, params.identity)
        {
            .style.setFont(dlg.theme().createDefaultFontFs(metrics.defaultFontSize - 1), .Regular)
            .style.addStyleSheetColors("label_Text $faintText")
            .dockStyle = .Top
            .setTextAlignment(.Left, .Top)
            .updateFlags(.AutoHeight)
        }

        let namesWidth = Math.max(stackLayout.position.width - tileWidth, 1)

        var namesHeight = dlg.labelMessageTitle.measure(Math.Point{namesWidth, 0}).preferred.y
        dlg.labelMessageTitle.position.height = namesHeight
        if params.identity.count
        {
            let identityHeight = dlg.labelIdentity.measure(Math.Point{namesWidth, 0}).preferred.y
            dlg.labelIdentity.position.height = identityHeight
            namesHeight += identityHeight
        }
        else
        {
            dlg.labelIdentity.hide()
        }

        // The name and its identity line stand on the middle of the tile, as one group.
        let headerTotal = Math.max(headerHeight, namesHeight)
        names.padding.y = Math.max(0, Math.round((headerTotal - namesHeight) * 0.5))
        dlg.identityView.position.height = headerTotal

        with dlg.labelMessage = Label.create(stackLayout, params.message, flags: .AutoHeight | .WordWrap | .SecondaryText)
        {
            .setTextAlignment(.Left, .Top)
        }

        if params.surfaceIcon.isValid()
        {
            var cpyIcon = params.surfaceIcon
            cpyIcon.sizeX, cpyIcon.sizeY = metrics.wnd_CaptionIconSize
            srf.setIcon(cpyIcon)
        }

        // One Close: it is the answer and the way out, so Escape presses it and no hint is shown.
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
        Swag.assert(title.count or content.count, "an about section carries no text")

        let metrics = .themeMetrics()
        if not .sectionsScroll
        {
            // Authored width, like the header above it: the column leaves the cross axis to each
            // of its children.

            with let scroll = Wnd.create'ScrollWnd(.contentStack, "", Math.Rectangle{0, 0, .contentStack.position.width, 0})
            {
                .padding = 0
                .updateFlags(.DisableHorizontal | .TransparentBars)
            }

            .sectionsScroll = scroll
            with .sectionsStack = scroll.createView'StackLayoutCtrl()
            {
                .mode    = .Top
                .spacing = metrics.dialog_BtnPadding
            }
        }

        let stack = unwrap .sectionsStack
        if title.count
        {
            // The heading is set through the rich-text marker rather than through a face of its
            // own, so it stays the family the theme gives the box and moves with it.
            let heading = Format.toString("<b>%</b>", title)
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
        let stack = .contentStack
        .applyLayout()

        let scroll = .sectionsScroll
        if scroll
        {
            // Measured against the width left once a bar is there, whether or not one is showing:
            // measured against the full viewport, the text would wrap one line further the moment
            // the bar appeared, and the column would need the room it was just told it had.
            let inner = unwrap .sectionsStack
            let bar   = .themeMetrics().scrollBar_Size
            let room  = Math.max(scroll.paddedClientRect().width - bar, 1)

            // The column's own content, not its measured size: a scroll view resizes its view to
            // the viewport, and a resized window answers for the size it was given. Rounded out,
            // because the window it goes in lands on whole units: a viewport a fraction shorter
            // than its content shows a scroll bar over a list that fits.
            let needed = Math.ceil(inner.itf.measureContent(Math.Point{room, 0}).y)
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

        if not .fitsToContent do
            return

        let availableWidth = Math.max(stack.position.width, 1)
        let contentHeight  = stack.measure(Math.Point{availableWidth, 0}).preferred.y
        .fitHeightToContent(contentHeight)
        if .parentSurface do
            .surface!.center(.parentSurface)
    }
}
