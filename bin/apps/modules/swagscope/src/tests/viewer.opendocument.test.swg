#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

private var openDocumentReportedDetails: String
private const OpenDocumentFixtureImage    = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgAQAAAABbAUdZAAAABGdBTUEAAYagMeiWXwAAAFtJREFUeJwtzLEJAzAMBdHr0gSySiALejRvkBU8gsGNCmFFB1Hx4IovqurSpIRszqklUwbnUzRXEuIRsiG/SyY9G0JzJSVei9qynm9qyjBpLp0pYW7pbzBl8L8fEIdJL9AvFMkAAAAASUVORK5CYII="
private const OpenDocumentFixtureStyles   = "<?xml version='1.0' encoding='UTF-8'?><office:document-styles xmlns:office='urn:o' xmlns:style='urn:style' xmlns:fo='urn:fo'><office:styles><style:style style:name='ExternalEmphasis' style:family='paragraph'><style:paragraph-properties fo:text-align='center'/><style:text-properties fo:font-weight='bold'/></style:style></office:styles></office:document-styles>"
private const OpenDocumentFixtureMetadata = "<?xml version='1.0' encoding='UTF-8'?><office:document-meta xmlns:office='urn:o' xmlns:dc='urn:dc'><office:meta><dc:title>  Quarterly &amp; review  </dc:title><dc:subject>Reader &#x72;egression</dc:subject><dc:creator>Swag Scope tests</dc:creator></office:meta></office:document-meta>"

private func openDocumentFixturePath(name: string)->String
{
    return Path.combine(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas"), name)
}

private func countOpenDocumentImageTags(html: string)->u64
{
    var result = 0'u64
    var at     = 0'u64
    while at < html.count
    {
        let found = Utf8.indexOf(html, "<img", at)
        if found == Swag.U64.Max do
            break
        result += 1
        at     = found + 4
    }

    return result
}

private func reportOpenDocumentTestDetails(view: *Wnd, details: string)
{
    discard view
    openDocumentReportedDetails = details
}

private struct OpenDocumentFixtureEntry
{
    name:  String
    plain: Array'u8
    crc32: u32
    local: u64
}

private func openDocumentFixtureU16(bytes: *Array'u8, value: u16)
{
    bytes.add(cast #bit (u8) value)
    bytes.add(cast #bit (u8) (value >> 8))
}

private func openDocumentFixtureU32(bytes: *Array'u8, value: u32)
{
    openDocumentFixtureU16(bytes, cast #bit (u16) value)
    openDocumentFixtureU16(bytes, cast #bit (u16) (value >> 16))
}

private func addOpenDocumentFixtureEntry(bytes: *Array'u8, entry: *OpenDocumentFixtureEntry)
{
    entry.local = bytes.count
    openDocumentFixtureU32(bytes, 0x04034B50)
    openDocumentFixtureU16(bytes, 20)
    openDocumentFixtureU16(bytes, 1 << 11)
    openDocumentFixtureU16(bytes, 0)
    openDocumentFixtureU16(bytes, 0)
    openDocumentFixtureU16(bytes, 0)
    openDocumentFixtureU32(bytes, entry.crc32)
    openDocumentFixtureU32(bytes, cast(u32) entry.plain.count)
    openDocumentFixtureU32(bytes, cast(u32) entry.plain.count)
    openDocumentFixtureU16(bytes, cast(u16) entry.name.length)
    openDocumentFixtureU16(bytes, 0)
    bytes.add(entry.name.toSlice())
    bytes.add(entry.plain.toSlice())
}

private func openDocumentMimeType(kind: OpenDocumentKind, template = false)->string
{
    if template
    {
        switch #complete kind
        {
        case .Text:         return "application/vnd.oasis.opendocument.text-template"
        case .Spreadsheet:  return "application/vnd.oasis.opendocument.spreadsheet-template"
        case .Presentation: return "application/vnd.oasis.opendocument.presentation-template"
        case .Drawing:      return "application/vnd.oasis.opendocument.graphics-template"
        }
    }

    switch #complete kind
    {
    case .Text:         return "application/vnd.oasis.opendocument.text"
    case .Spreadsheet:  return "application/vnd.oasis.opendocument.spreadsheet"
    case .Presentation: return "application/vnd.oasis.opendocument.presentation"
    case .Drawing:      return "application/vnd.oasis.opendocument.graphics"
    }
}

private func buildOpenDocumentFixture(kind: OpenDocumentKind, content: string, template = false)->Array'u8
{
    var entries: [5] OpenDocumentFixtureEntry
    entries[0].name = "mimetype"
    entries[0].plain.add(openDocumentMimeType(kind, template))
    entries[0].crc32 = Hash.Crc32.compute(entries[0].plain.toSlice())
    entries[1].name  = "content.xml"
    entries[1].plain.add(content)
    entries[1].crc32 = Hash.Crc32.compute(entries[1].plain.toSlice())
    entries[2].name  = "Pictures/figure.png"
    entries[2].plain = expect Base64.decode(OpenDocumentFixtureImage)
    entries[2].crc32 = Hash.Crc32.compute(entries[2].plain.toSlice())
    entries[3].name  = "styles.xml"
    entries[3].plain.add(OpenDocumentFixtureStyles)
    entries[3].crc32 = Hash.Crc32.compute(entries[3].plain.toSlice())
    entries[4].name  = "meta.xml"
    entries[4].plain.add(OpenDocumentFixtureMetadata)
    entries[4].crc32 = Hash.Crc32.compute(entries[4].plain.toSlice())

    var result: retval
    for &entry in entries do
        addOpenDocumentFixtureEntry(&result, entry)

    let directoryAt = result.count
    for entry in entries
    {
        openDocumentFixtureU32(&result, 0x02014B50)
        openDocumentFixtureU16(&result, 20)
        openDocumentFixtureU16(&result, 20)
        openDocumentFixtureU16(&result, 1 << 11)
        openDocumentFixtureU16(&result, 0)
        openDocumentFixtureU16(&result, 0)
        openDocumentFixtureU16(&result, 0)
        openDocumentFixtureU32(&result, entry.crc32)
        openDocumentFixtureU32(&result, cast(u32) entry.plain.count)
        openDocumentFixtureU32(&result, cast(u32) entry.plain.count)
        openDocumentFixtureU16(&result, cast(u16) entry.name.length)
        openDocumentFixtureU16(&result, 0)
        openDocumentFixtureU16(&result, 0)
        openDocumentFixtureU16(&result, 0)
        openDocumentFixtureU16(&result, 0)
        openDocumentFixtureU32(&result, 0)
        openDocumentFixtureU32(&result, cast(u32) entry.local)
        result.add(entry.name.toSlice())
    }

    let directorySize = result.count - directoryAt
    openDocumentFixtureU32(&result, 0x06054B50)
    openDocumentFixtureU16(&result, 0)
    openDocumentFixtureU16(&result, 0)
    openDocumentFixtureU16(&result, entries.count)
    openDocumentFixtureU16(&result, entries.count)
    openDocumentFixtureU32(&result, cast(u32) directorySize)
    openDocumentFixtureU32(&result, cast(u32) directoryAt)
    openDocumentFixtureU16(&result, 0)
    return result
}

private func writeOpenDocumentFixture(extension: string, kind: OpenDocumentKind, content: string, template = false)->String
{
    let fileName = Gui.Testing.tempFilePath("scope-opendocument-", extension)
    discard expect File.writeAllBytes(fileName, buildOpenDocumentFixture(kind, content, template).toSlice())
    return fileName
}

private func writeOpenDocumentFlatFixture(extension: string, content: string)->String
{
    let fileName = Gui.Testing.tempFilePath("scope-opendocument-", extension)
    discard expect File.writeAllBytes(fileName, content)
    return fileName
}

private func openDocumentXml(body: string, styles: string = "")->String
{
    return Format.toString("<?xml version=\"1.0\" encoding=\"UTF-8\"?><office:document-content xmlns:office=\"urn:o\" xmlns:text=\"urn:t\" xmlns:table=\"urn:table\" xmlns:draw=\"urn:draw\" xmlns:xlink=\"urn:xlink\" xmlns:style=\"urn:style\" xmlns:fo=\"urn:fo\">%<office:body>%</office:body></office:document-content>", styles, body)
}

private func textOpenDocumentXml()->String
{
    let styles = "<office:automatic-styles><style:style style:name='Emphasis' style:family='text'><style:text-properties fo:font-weight='bold' fo:font-style='italic' fo:font-size='18pt'/></style:style><style:style style:name='Underline' style:family='text'><style:text-properties style:text-underline-style='solid'/></style:style><style:style style:name='Revision' style:family='text'><style:text-properties style:text-line-through-style='solid'/></style:style><style:style style:name='Raised' style:family='text'><style:text-properties style:text-position='super 58%'/></style:style><text:list-style style:name='Numbered'><text:list-level-style-number text:level='1'/></text:list-style></office:automatic-styles>"
    return openDocumentXml("<office:text><text:h text:outline-level='1'>Quarterly report</text:h><text:bookmark-start text:name='summary target'/><text:p><text:a xlink:href='#summary target'>Read the summary</text:a> <text:a xlink:href='javascript:alert(1)'>Unsafe action</text:a></text:p><text:p>Paris &amp; Berlin <text:span text:style-name='Emphasis'>remain</text:span> <text:a xlink:href='https://www.swag-lang.org/?viewer=odf&amp;kind=text'><text:span text:style-name='Underline'>readable</text:span><text:span text:style-name='Raised'>1</text:span></text:a> <text:note><text:note-citation>2</text:note-citation><text:note-body><text:p>Stored footnote.</text:p></text:note-body></text:note> <text:span text:style-name='Revision'>outdated</text:span>.</text:p><text:p text:style-name='ExternalEmphasis'>Style from styles.xml</text:p><text:list><text:list-item><text:p>Reviewed</text:p></text:list-item></text:list><text:list text:style-name='Numbered'><text:list-item><text:p>Prioritized</text:p></text:list-item></text:list><table:table table:name=\"Summary\"><table:table-header-rows><table:table-row><table:table-cell><text:p>City</text:p></table:table-cell><table:table-cell><text:p>Budget</text:p></table:table-cell></table:table-row></table:table-header-rows><table:table-row><table:table-cell><text:p>Paris</text:p></table:table-cell><table:table-cell><text:p>42</text:p></table:table-cell></table:table-row></table:table><draw:frame svg:width='48px' svg:height='48px'><draw:image xlink:href='Pictures/figure.png'/></draw:frame><draw:frame><draw:image xlink:href='https://example.com/remote.png'/></draw:frame></office:text>", styles)
}

private func inlineImageOpenDocumentXml()->String
{
    var frames: String
    frames += "<draw:frame><draw:image xlink:href='data:image/svg+xml;base64,PHN2Zy8+'/></draw:frame>"
    frames += "<draw:frame><draw:image xlink:href='data:image/png;base64,not@base64'/></draw:frame>"
    frames += Format.toString("<draw:frame><draw:image xlink:href='data:image/PNG;base64,%'/></draw:frame>", OpenDocumentFixtureImage)
    for 256 do
        frames += Format.toString("<draw:frame><draw:image xlink:href='data:image/png;base64,%'/></draw:frame>", OpenDocumentFixtureImage)
    return openDocumentXml(Format.toString("<office:text><text:p>Inline raster images</text:p>%</office:text>", frames.toString()).toString())
}

private func spreadsheetOpenDocumentXml()->String
{
    return openDocumentXml("<office:spreadsheet><table:table table:name=\"Budget\"><table:table-row><table:table-cell><text:p>City</text:p></table:table-cell><table:table-cell><text:p>Budget</text:p></table:table-cell></table:table-row><table:table-row><table:table-cell><text:p>Paris</text:p></table:table-cell><table:table-cell office:value=\"42\"></table:table-cell></table:table-row><table:table-row><table:table-cell><text:p>Berlin</text:p></table:table-cell><table:table-cell table:formula=\"of:=SUM([.B2])\" office:value=\"58\"></table:table-cell></table:table-row></table:table><table:table table:name=\"Forecast\"><table:table-row><table:table-cell><text:p>City</text:p></table:table-cell><table:table-cell><text:p>Budget</text:p></table:table-cell></table:table-row><table:table-row><table:table-cell><text:p>Lyon</text:p></table:table-cell><table:table-cell><text:p>73</text:p></table:table-cell></table:table-row></table:table></office:spreadsheet>")
}

private func presentationOpenDocumentXml()->String
{
    return openDocumentXml("<office:presentation><draw:page draw:name=\"Launch\"><draw:text-box><text:h>Launch</text:h><text:p>Prepare the offline review.</text:p></draw:text-box><draw:frame><draw:image xlink:href='Pictures/figure.png'/></draw:frame></draw:page><draw:page draw:name=\"Review\"><draw:text-box><text:h>Review</text:h><text:p>Offline review is ready.</text:p></draw:text-box></draw:page></office:presentation>")
}

private func drawingOpenDocumentXml()->String
{
    return openDocumentXml("<office:drawing><draw:page draw:name=\"Diagram\"><draw:text-box><text:h>Diagram</text:h><text:p>Read-only drawing page.</text:p></draw:text-box><draw:frame svg:width='48px' svg:height='48px'><draw:image xlink:href='Pictures/figure.png'/></draw:frame></draw:page><draw:page draw:name=\"Delivery\"><draw:text-box><text:h>Delivery</text:h><text:p>Drawing handoff is ready.</text:p></draw:text-box></draw:page></office:drawing>")
}

// The container reader preserves the readable structures of each supported OpenDocument family.
#test
{
    let text = expect parseOpenDocumentContent(textOpenDocumentXml().toString(), .Text)
    Swag.assert(Utf8.contains(text.html.toString(), "<h1>Quarterly report</h1>"))
    Swag.assert(Utf8.contains(text.html.toString(), "Paris &amp; Berlin"))
    Swag.assert(Utf8.contains(text.html.toString(), "<span id=\"odf-bookmark-1\"></span>") and Utf8.contains(text.html.toString(), "href=\"#odf-bookmark-1\"") and !Utf8.contains(text.html.toString(), "javascript:"))
    Swag.assert(Utf8.contains(text.html.toString(), "href=\"https://www.swag-lang.org/?viewer=odf&amp;kind=text\""))
    Swag.assert(Utf8.contains(text.html.toString(), "<span style=\"font-size:150%\"><strong><em>remain</em></strong></span>") and Utf8.contains(text.html.toString(), "<u>readable</u>") and Utf8.contains(text.html.toString(), "<sup>1</sup>") and Utf8.contains(text.html.toString(), "<sup>2</sup>") and Utf8.contains(text.html.toString(), "<s>outdated</s>"))
    Swag.assert(Utf8.contains(text.html.toString(), "<blockquote><p>Stored footnote.</p></blockquote>"))
    Swag.assert(Utf8.contains(text.html.toString(), "<table>"))
    Swag.assert(Utf8.contains(text.html.toString(), "<th><p>City</p></th><th><p>Budget</p></th>"))
    Swag.assert(Utf8.contains(text.html.toString(), "<ol><li><p>Prioritized</p></li></ol>"))
    Swag.assert(!Utf8.contains(text.html.toString(), "example.com"))

    let inlineImages = expect parseOpenDocumentContent(inlineImageOpenDocumentXml().toString(), .Text)
    Swag.assert(countOpenDocumentImageTags(inlineImages.html.toString()) == 256)
    Swag.assert(Utf8.contains(inlineImages.html.toString(), "data:image/PNG;base64,"))
    Swag.assert(!Utf8.contains(inlineImages.html.toString(), "svg+xml") and !Utf8.contains(inlineImages.html.toString(), "not@base64"))

    let spreadsheet = expect parseOpenDocumentContent(spreadsheetOpenDocumentXml().toString(), .Spreadsheet)
    Swag.assert(spreadsheet.sheets.count == 2)
    Swag.assert(spreadsheet.sheets[0].name == "Budget" and spreadsheet.sheets[0].table.columns.count == 2 and spreadsheet.sheets[0].table.rows.count == 2)
    Swag.assert(spreadsheet.sheets[0].table.columns[0] == "City" and spreadsheet.sheets[0].table.columns[1] == "Budget")
    Swag.assert(spreadsheet.sheets[0].table.rows[0].cells[0] == "Paris" and spreadsheet.sheets[0].table.rows[0].cells[1] == "42")
    Swag.assert(spreadsheet.sheets[0].table.rows[1].cells[0] == "Berlin" and spreadsheet.sheets[0].table.rows[1].cells[1] == "58")
    Swag.assert(spreadsheet.sheets[1].name == "Forecast" and spreadsheet.sheets[1].table.rows.count == 1 and spreadsheet.sheets[1].table.rows[0].cells[0] == "Lyon")

    let presentation = expect parseOpenDocumentContent(presentationOpenDocumentXml().toString(), .Presentation)
    Swag.assert(presentation.slides.count == 2 and presentation.slides[0].name == "Launch" and presentation.slides[1].name == "Review")
    Swag.assert(Utf8.contains(presentation.slides[0].html.toString(), "Prepare the offline review") and Utf8.contains(presentation.slides[1].html.toString(), "Offline review is ready"))

    let drawing = expect parseOpenDocumentContent(drawingOpenDocumentXml().toString(), .Drawing)
    Swag.assert(drawing.slides.count == 2 and drawing.slides[0].name == "Diagram" and drawing.slides[1].name == "Delivery")
    Swag.assert(Utf8.contains(drawing.slides[0].html.toString(), "Read-only drawing page") and Utf8.contains(drawing.slides[1].html.toString(), "Drawing handoff is ready"))
}

// Repeated ODF rows and cells cannot expand a small source document into an unbounded table model.
#test
{
    var repeatedRows: String
    for 25 do
        repeatedRows += "<table:table-row table:number-rows-repeated='4096'><table:table-cell office:value='1'/></table:table-row>"
    let rowSource = openDocumentXml(Format.toString("<office:spreadsheet><table:table table:name='Bounded'>%</table:table></office:spreadsheet>", repeatedRows.toString()).toString())
    discard catch parseOpenDocumentContent(rowSource.toString(), .Spreadsheet) as rowError
    Swag.assert(rowError != null and Utf8.contains(Errors.message(rowError), "100,000 rows"))

    let cellSource = openDocumentXml("<office:spreadsheet><table:table table:name='Bounded'><table:table-row table:number-rows-repeated='4096'><table:table-cell table:number-columns-repeated='256' office:value='1'/></table:table-row></table:table></office:spreadsheet>")
    discard catch parseOpenDocumentContent(cellSource.toString(), .Spreadsheet) as cellError
    Swag.assert(cellError != null and Utf8.contains(Errors.message(cellError), "1,000,000 cells"))
}

// CC0 files created outside this repository keep archive parsing and the three reader surfaces honest.
#test
{
    {
        var host: Testing.HeadlessHost
        host.setup(820, 560)
        defer host.shutdown()
        var result = openTestViewer(openDocumentViewerPlugin(), &host.root, openDocumentFixturePath("odf-cc0-tables.odt").toString())
        let view   = cast(*OpenDocumentViewer) result.view!
        completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
        Swag.assert((view.html != null) and Utf8.contains(view.document.html.toString(), "Document with Tables") and result.info!.isVisible())
    }

    {
        var host: Testing.HeadlessHost
        host.setup(820, 560)
        defer host.shutdown()
        var result = openTestViewer(openDocumentViewerPlugin(), &host.root, openDocumentFixturePath("odf-cc0-1000rows.ods").toString())
        let view   = cast(*OpenDocumentViewer) result.view!
        completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
        Swag.assert((view.table != null) and view.document.sheets.count == 1 and view.table.document.columns.count >= 5 and view.table.document.rows.count >= 1_000 and result.info!.isHidden())
    }

    {
        var host: Testing.HeadlessHost
        host.setup(820, 560)
        defer host.shutdown()
        var result = openTestViewer(openDocumentViewerPlugin(), &host.root, openDocumentFixturePath("odf-cc0-10slides.odp").toString())
        let view   = cast(*OpenDocumentViewer) result.view!
        completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
        Swag.assert((view.html != null) and view.document.slides.count == 10 and Utf8.contains(view.document.slides[0].html.toString(), "Sample Presentation") and result.info!.isVisible())
    }
}

// Flat XML and templates select the same bounded reader without requiring a ZIP container.
#test
{
    let flatFileName = writeOpenDocumentFlatFixture(".fods", spreadsheetOpenDocumentXml().toString())
    defer discard catch File.delete(flatFileName)
    var flatHost: Testing.HeadlessHost
    flatHost.setup(820, 560)
    defer flatHost.shutdown()
    var flatResult = openTestViewer(openDocumentViewerPlugin(), &flatHost.root, flatFileName.toString())
    let flatView   = cast(*OpenDocumentViewer) flatResult.view!
    completeViewerBackgroundLoad(&flatHost, &flatView.load, flatView.loadTimer)
    Swag.assert((flatView.table != null) and flatView.document.sheets.count == 2 and flatView.table.document.columns.count == 2 and flatView.table.document.rows.count == 2)

    let templateFileName = writeOpenDocumentFixture(".ott", .Text, textOpenDocumentXml().toString(), true)
    defer discard catch File.delete(templateFileName)
    var templateHost: Testing.HeadlessHost
    templateHost.setup(820, 560)
    defer templateHost.shutdown()
    var templateResult = openTestViewer(openDocumentViewerPlugin(), &templateHost.root, templateFileName.toString())
    let templateView   = cast(*OpenDocumentViewer) templateResult.view!
    completeViewerBackgroundLoad(&templateHost, &templateView.load, templateView.loadTimer)
    Swag.assert((templateView.html != null) and Utf8.contains(templateView.document.html.toString(), "Quarterly report"))
}

// ODG keeps each drawing page searchable without trying to execute drawing content or macros.
#test
{
    let flatFileName = writeOpenDocumentFlatFixture(".fodg", drawingOpenDocumentXml().toString())
    defer discard catch File.delete(flatFileName)
    var flatHost: Testing.HeadlessHost
    flatHost.setup(820, 560)
    defer flatHost.shutdown()
    var flatResult = openTestViewer(openDocumentViewerPlugin(), &flatHost.root, flatFileName.toString())
    let flatView   = cast(*OpenDocumentViewer) flatResult.view!
    completeViewerBackgroundLoad(&flatHost, &flatView.load, flatView.loadTimer)
    Swag.assert((flatView.html != null) and !(flatView.table != null) and flatView.document.kind == .Drawing and flatView.document.slides.count == 2)
    Swag.assert(flatResult.info != null and flatResult.info!.isVisible() and flatView.pageCombo.items.count == 2 and flatView.pageCombo.toolTip == openDocumentStrings().ui_TipPage)

    flatView.pageCombo.setSelectedIndex(1)
    Swag.assert(flatView.slideIndex == 1 and Utf8.contains(flatView.document.slides[flatView.slideIndex].html.toString(), "Drawing handoff is ready"))
    var previous = KeyEvent{kind: .Pressed, key: .Left}
    flatView.sendEvent(&previous)
    Swag.assert(previous.accepted and flatView.slideIndex == 0)
    var last = KeyEvent{kind: .Pressed, key: .End}
    flatView.sendEvent(&last)
    Swag.assert(last.accepted and flatView.slideIndex == 1)
    var matches: Array'Viewer.SearchMatch
    collectViewerMatches(flatResult.collectMatches!, flatResult.view!, "Read-only drawing page", &matches)
    Swag.assert(matches.count == 1 and matches[0].major == 0 and flatResult.revealMatch!(flatResult.view!, matches[0], "Read-only drawing page"))
    Swag.assert(flatView.slideIndex == 0)

    let templateFileName = writeOpenDocumentFixture(".otg", .Drawing, drawingOpenDocumentXml().toString(), true)
    defer discard catch File.delete(templateFileName)
    var templateHost: Testing.HeadlessHost
    templateHost.setup(820, 560)
    defer templateHost.shutdown()
    var templateResult = openTestViewer(openDocumentViewerPlugin(), &templateHost.root, templateFileName.toString())
    let templateView   = cast(*OpenDocumentViewer) templateResult.view!
    completeViewerBackgroundLoad(&templateHost, &templateView.load, templateView.loadTimer)
    Swag.assert((templateView.html != null) and templateView.document.kind == .Drawing and Utf8.contains(templateView.document.slides[0].html.toString(), "Read-only drawing page"))
}

// ODT uses the offline HTML document surface and exposes its rendered text through shared search.
#test
{
    let fileName = writeOpenDocumentFixture(".odt", .Text, textOpenDocumentXml().toString())
    defer discard catch File.delete(fileName)

    openDocumentReportedDetails.clear()

    var host: Testing.HeadlessHost
    host.setup(820, 560)
    defer host.shutdown()
    var result = openTestViewer(openDocumentViewerPlugin(), &host.root, fileName.toString(), services: {reportDetails: &reportOpenDocumentTestDetails})
    Swag.assert(result.view != null and result.isLoading != null and result.collectMatches != null and result.revealMatch != null and result.searchBounds != null)

    let view = cast(*OpenDocumentViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    Swag.assert((view.html != null) and !(view.table != null))
    Swag.assert(view.html.elementById("odf-bookmark-1") != HtmlNoNode and view.html.navigateToFragment("#odf-bookmark-1"))
    Swag.assert(result.info != null)
    assertViewerInfoButton(view.zoomLabel)
    Swag.assert(result.info!.preferredSize.x == ViewerZoomSlotWidth)
    Swag.assert(view.document.metadata.title == "Quarterly & review" and view.document.metadata.subject == "Reader regression" and view.document.metadata.creator == "Swag Scope tests")
    Swag.assert(Utf8.contains(openDocumentReportedDetails.toString(), "OpenDocument") and Utf8.contains(openDocumentReportedDetails.toString(), "Quarterly & review"))
    Swag.assert(Utf8.contains(view.document.html.toString(), "data:image/png;base64,") and Utf8.contains(view.document.html.toString(), "width=\"") and Utf8.contains(view.document.html.toString(), "height=\"") and Utf8.contains(view.document.html.toString(), "<p align=\"center\"><strong>Style from styles.xml</strong></p>") and !Utf8.contains(view.document.html.toString(), "example.com"))

    var zoomIn = KeyEvent{kind: .Pressed, key: .OemPlus, modifiers: .Control}
    view.sendEvent(&zoomIn)
    Swag.assert(zoomIn.accepted and view.zoomPercent == 125 and view.html.documentStyle.bodyFontSize == 20)
    var resetZoom = KeyEvent{kind: .Pressed, key: .D0, modifiers: .Control}
    view.sendEvent(&resetZoom)
    Swag.assert(resetZoom.accepted and view.zoomPercent == 100 and view.html.documentStyle.bodyFontSize == 16)

    var matches: Array'Viewer.SearchMatch
    collectViewerMatches(result.collectMatches!, result.view!, "Berlin", &matches)
    Swag.assert(matches.count == 1 and result.revealMatch!(result.view!, matches[0], "Berlin"))
    var bounds: Math.Rectangle
    Swag.assert(result.searchBounds!(result.view!, matches[0], &bounds) and !bounds.isEmpty())
    result.clearSearch!(result.view!)
}

// ODS exposes every sheet through one compact control while keeping one virtual table active.
#test
{
    let fileName = writeOpenDocumentFixture(".ods", .Spreadsheet, spreadsheetOpenDocumentXml().toString())
    defer discard catch File.delete(fileName)

    openDocumentReportedDetails.clear()

    var host: Testing.HeadlessHost
    host.setup(820, 560)
    defer
    {
        discard catch host.app.setLanguage(ReferenceLanguage)
        host.shutdown()
    }

    var result = openTestViewer(openDocumentViewerPlugin(), &host.root, fileName.toString(), services: {reportDetails: &reportOpenDocumentTestDetails})
    let view   = cast(*OpenDocumentViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    host.root.applyLayout()
    discard host.render(&host.root)
    Swag.assert((view.table != null) and view.document.sheets.count == 2 and view.table.document.columns.count == 2 and view.table.document.rows.count == 2)
    Swag.assert(result.info != null and result.info!.isHidden())
    Swag.assert(view.pageCombo.items.count == 2 and view.pageCombo.selectedIndex == 0 and view.pageCombo.toolTip == openDocumentStrings().ui_TipSheet)

    view.pageCombo.setSelectedIndex(1)
    Swag.assert(view.sheetIndex == 1 and view.table.document.rows.count == 1 and view.table.document.rows[0].cells[0] == "Lyon")
    view.pageCombo.setSelectedIndex(0)
    Swag.assert(view.sheetIndex == 0 and view.table.document.rows.count == 2 and view.table.document.rows[1].cells[0] == "Berlin")

    var matches: Array'Viewer.SearchMatch
    collectViewerMatches(result.collectMatches!, result.view!, "Lyon", &matches)
    Swag.assert(matches.count == 1 and matches[0].major == 1 and result.revealMatch!(result.view!, matches[0], "Lyon"))
    Swag.assert(view.sheetIndex == 1 and view.table.document.rows[0].cells[0] == "Lyon")
    var bounds: Math.Rectangle
    Swag.assert(result.searchBounds!(result.view!, matches[0], &bounds) and !bounds.isEmpty())
    result.clearSearch!(result.view!)

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    host.root.applyLayout()
    discard host.render(&host.root)
    Swag.assert(view.pageCombo.toolTip == "Choisir une feuille de calcul" and Utf8.contains(openDocumentReportedDetails.toString(), "feuille de calcul"))
    Testing.assertContentFits(view.commands)
}

// ODP keeps one readable slide active while search and the selector cover the whole presentation.
#test
{
    let fileName = writeOpenDocumentFixture(".odp", .Presentation, presentationOpenDocumentXml().toString())
    defer discard catch File.delete(fileName)

    openDocumentReportedDetails.clear()

    var host: Testing.HeadlessHost
    host.setup(820, 560)
    defer
    {
        discard catch host.app.setLanguage(ReferenceLanguage)
        host.shutdown()
    }

    var result = openTestViewer(openDocumentViewerPlugin(), &host.root, fileName.toString(), services: {reportDetails: &reportOpenDocumentTestDetails})
    let view   = cast(*OpenDocumentViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    Swag.assert((view.html != null) and !(view.table != null) and view.document.slides.count == 2)
    Swag.assert(view.pageCombo.items.count == 2 and view.pageCombo.selectedIndex == 0 and view.pageCombo.toolTip == openDocumentStrings().ui_TipSlide)

    view.pageCombo.setSelectedIndex(1)
    Swag.assert(view.slideIndex == 1 and Utf8.contains(view.document.slides[view.slideIndex].html.toString(), "Offline review is ready"))
    view.pageCombo.setSelectedIndex(0)
    Swag.assert(view.slideIndex == 0 and Utf8.contains(view.document.slides[view.slideIndex].html.toString(), "Prepare the offline review"))

    var matches: Array'Viewer.SearchMatch
    collectViewerMatches(result.collectMatches!, result.view!, "Offline review is ready", &matches)
    Swag.assert(matches.count == 1 and matches[0].major == 1 and result.revealMatch!(result.view!, matches[0], "Offline review is ready"))
    Swag.assert(view.slideIndex == 1)
    var bounds: Math.Rectangle
    Swag.assert(result.searchBounds!(result.view!, matches[0], &bounds) and !bounds.isEmpty())
    result.clearSearch!(result.view!)

    var previous = KeyEvent{kind: .Pressed, key: .Left}
    view.sendEvent(&previous)
    Swag.assert(previous.accepted and view.slideIndex == 0)
    var firstEdge = KeyEvent{kind: .Pressed, key: .Left}
    view.sendEvent(&firstEdge)
    Swag.assert(!firstEdge.accepted and view.slideIndex == 0)
    var next = KeyEvent{kind: .Pressed, key: .Right}
    view.sendEvent(&next)
    Swag.assert(next.accepted and view.slideIndex == 1)
    var first = KeyEvent{kind: .Pressed, key: .Home}
    view.sendEvent(&first)
    Swag.assert(first.accepted and view.slideIndex == 0)
    var last = KeyEvent{kind: .Pressed, key: .End}
    view.sendEvent(&last)
    Swag.assert(last.accepted and view.slideIndex == 1)
    var previousPage = KeyEvent{kind: .Pressed, key: .PageUp}
    view.sendEvent(&previousPage)
    Swag.assert(previousPage.accepted and view.slideIndex == 0)
    var nextPage = KeyEvent{kind: .Pressed, key: .PageDown}
    view.sendEvent(&nextPage)
    Swag.assert(nextPage.accepted and view.slideIndex == 1)

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    host.root.applyLayout()
    discard host.render(&host.root)
    Swag.assert(view.pageCombo.toolTip == "Choisir une diapositive" and Utf8.contains(openDocumentReportedDetails.toString(), "présentation"))
    Testing.assertContentFits(view.commands)
}

// A compact selector gives every sheet a stable place without displacing the active table.
#[Swag.TestTag("golden")]
#test
{
    let fileName = writeOpenDocumentFixture(".ods", .Spreadsheet, spreadsheetOpenDocumentXml().toString())
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer
    {
        discard catch host.app.setLanguage(ReferenceLanguage)
        host.shutdown()
    }

    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let commandBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 52})
    commandBar.dockStyle       = .Bottom
    commandBar.backgroundStyle = .Window
    commandBar.padding         = {16, 8, 16, 8}

    var result = openTestViewer(openDocumentViewerPlugin(), &host.root, fileName.toString(), commandParent: commandBar)
    Swag.assert(result.view != null and result.commands != null)
    commandBar.centerGroup = result.commands

    let view = cast(*OpenDocumentViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    view.dockStyle          = .Center
    view.commands.dockStyle = .None
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(view.commands)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.opendocument.spreadsheet")

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    host.root.applyLayout()
    var french = host.render(&host.root)
    discard french
    Swag.assert(view.pageCombo.toolTip == "Choisir une feuille de calcul")
    Testing.assertContentFits(view.commands)
}

// The presentation selector leaves the active slide as the dominant document surface.
#[Swag.TestTag("golden")]
#test
{
    let fileName = writeOpenDocumentFixture(".odp", .Presentation, presentationOpenDocumentXml().toString())
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer
    {
        discard catch host.app.setLanguage(ReferenceLanguage)
        host.shutdown()
    }

    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let commandBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 52})
    commandBar.dockStyle       = .Bottom
    commandBar.backgroundStyle = .Window
    commandBar.padding         = {16, 8, 16, 8}

    let infoBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 40})
    infoBar.dockStyle       = .Top
    infoBar.backgroundStyle = .InformationBar
    infoBar.padding         = {16, 4, 16, 4}

    var result = openTestViewer(openDocumentViewerPlugin(), &host.root, fileName.toString(), commandParent: commandBar, infoParent: infoBar)
    Swag.assert(result.view != null and result.commands != null and result.info != null)
    commandBar.centerGroup = result.commands
    infoBar.centerGroup    = result.info

    let view = cast(*OpenDocumentViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    view.dockStyle          = .Center
    view.commands.dockStyle = .None
    result.info!.dockStyle  = .None
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(view.commands)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.opendocument.presentation")

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    host.root.applyLayout()
    var french = host.render(&host.root)
    discard french
    Swag.assert(view.pageCombo.toolTip == "Choisir une diapositive")
    Testing.assertContentFits(view.commands)
}

// The rendered document exposes its reading zoom in the ordinary information band.
#[Swag.TestTag("golden")]
#test
{
    let fileName = writeOpenDocumentFixture(".odt", .Text, textOpenDocumentXml().toString())
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(820, 560)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let infoBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 40})
    infoBar.dockStyle       = .Top
    infoBar.backgroundStyle = .InformationBar
    infoBar.padding         = {16, 4, 16, 4}
    var result = openTestViewer(openDocumentViewerPlugin(), &host.root, fileName.toString(), infoParent: infoBar)
    Swag.assert(result.info != null)
    infoBar.centerGroup = result.info
    let view = cast(*OpenDocumentViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    view.dockStyle         = .Center
    result.info!.dockStyle = .None
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(&host.root)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.opendocument.document")
}
