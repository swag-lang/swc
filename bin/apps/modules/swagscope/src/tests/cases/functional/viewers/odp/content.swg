#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// An expanded generated briefing keeps speaker notes separate and preserves vector drawing bounds.
#test
{
    let presentation = expect Odp.load(scopeTestDataPath("viewer.watershed.odp"))
    Swag.require(presentation.slides.count == 3)
    let slide = &presentation.slides[2]
    Swag.require(slide.title == "Field station status" and slide.shapes.count == 5)
    Swag.require(slide.shapes[1].round and slide.shapes[1].positioned)
    Swag.require(Utf8.contains(slide.shapes[1].plainText, "North Marsh"))
    Swag.require(slide.shapes[2].unsupported and slide.shapes[2].positioned)
    Swag.require(slide.shapes[3].unsupported and slide.shapes[3].positioned)
    Swag.require(slide.simplified and Utf8.contains(slide.notesHtml, "Recalibrate the lower marker"))
    Swag.require(presentation.omittedImages == 0)
}

// Master dimensions, static drawings and backgrounds survive, while master placeholder text stays out.
#test
{
    let styles = """<styles><page-layout name="Wide"><page-layout-properties page-width="10in" page-height="5.625in"/></page-layout><style name="Paper" family="drawing-page"><drawing-page-properties fill="solid" fill-color="#dff1e8"/></style><style name="Green" family="graphic"><graphic-properties fill="solid" fill-color="#216a56" stroke="none"/></style><master-page name="Master" page-layout-name="Wide" style-name="Paper"><rect style-name="Green" x="0in" y="5in" width="10in" height="0.5in"/><frame placeholder="true" class="title" x="0in" y="0in" width="8in" height="1in"><text-box><p>Master placeholder</p></text-box></frame></master-page></styles>"""
    let path   = odpTestPackage("""<draw:page draw:name="Reading" draw:master-page-name="Master"><draw:frame svg:x="0.5in" svg:y="0.5in" svg:width="8in" svg:height="1in"><draw:text-box><text:p>Actual page text</text:p></draw:text-box></draw:frame></draw:page>""", styles)
    defer discard catch File.delete(path)
    let presentation = expect Odp.load(path)
    let page         = &presentation.slides[0]
    Swag.require(Math.abs(presentation.width - 960) < 0.01 and Math.abs(presentation.height - 540) < 0.01)
    Swag.require(page.background == "dff1e8" and page.shapes.count == 2)
    Swag.require(page.shapes[0].fill == "216a56")
    Swag.require(Utf8.contains(page.readingHtml(), "Actual page text") and not Utf8.contains(page.readingHtml(), "Master placeholder"))
}

// ODF presentation styles and paragraph/span resets compose into scalable authored type.
#test
{
    let styles = """<styles><style name="Base" family="presentation"><text-properties font-size="20pt" font-weight="bold" color="#216a56"/></style><style name="Quiet" family="paragraph"><text-properties font-weight="normal" font-size="150%"/></style><style name="Small" family="text"><text-properties font-size="50%" font-style="italic"/></style></styles>"""
    let path   = odpTestPackage("""<draw:page draw:name="Type"><draw:frame presentation:style-name="Base" svg:x="0in" svg:y="0in" svg:width="8in" svg:height="2in"><draw:text-box><text:p text:style-name="Quiet">Quiet <text:span text:style-name="Small">detail</text:span></text:p></draw:text-box></draw:frame></draw:page>""", styles)
    defer discard catch File.delete(path)
    let presentation = expect Odp.load(path)
    let html         = presentation.slides[0].shapes[0].html
    Swag.require(Utf8.contains(html, "font-weight:normal;") and Utf8.contains(html, "<i>detail</i>"))
    Swag.require(Utf8.contains(html, "font-size:4.1667vw;") and Utf8.contains(html, "font-size:2.0833vw;"))
    Swag.require(Utf8.contains(html, "color:#216a56"))
}

// Notes, comments and active content cannot enter a slide's reading text.
#test
{
    let path = odpTestPackage("""<draw:page draw:name="Quiet"><draw:frame svg:x="0in" svg:y="0in" svg:width="8in" svg:height="2in"><draw:text-box><text:p>Before<office:annotation><text:p>Private comment</text:p></office:annotation>After</text:p></draw:text-box></draw:frame><presentation:notes><draw:frame><draw:text-box><text:p>Speaker secret</text:p></draw:text-box></draw:frame></presentation:notes><office:scripts><text:p>Script text</text:p></office:scripts></draw:page>""")
    defer discard catch File.delete(path)
    let presentation = expect Odp.load(path)
    let html         = presentation.slides[0].readingHtml()
    Swag.require(Utf8.contains(html, "BeforeAfter"))
    Swag.require(not Utf8.contains(html, "Private comment") and
                 not Utf8.contains(html, "Speaker secret") and
                 not Utf8.contains(html, "Script text"))
}

// External/traversing image references remain explicit omissions and do not fetch resources.
#test
{
    for target in ["https://example.invalid/picture.jpg", "%2e%2e/picture.jpg", "file:///tmp/picture.jpg"]
    {
        let body = Format.toString("""<draw:page draw:name="Images"><draw:frame svg:x="0in" svg:y="0in" svg:width="4in" svg:height="3in"><draw:image xlink:href="%"/></draw:frame></draw:page>""", target)
        let path = odpTestPackage(body)
        defer discard catch File.delete(path)
        let presentation = expect Odp.load(path)
        Swag.require(presentation.omittedImages == 1 and not Utf8.contains(presentation.slides[0].canvasHtml(960, 720), "<img"))
        Swag.require(Utf8.contains(presentation.slides[0].readingHtml(), Pptx.texts().ui_ImageOmitted))
    }
}

// Unsupported group transforms use explicit readable fallback; hidden slides retain their label.
#test
{
    let path = odpTestPackage("""<draw:page draw:name="Grouped" presentation:visibility="hidden"><draw:g draw:transform="rotate(0.5)"><draw:frame svg:x="0in" svg:y="0in" svg:width="4in" svg:height="2in"><draw:text-box><text:p>Still readable</text:p></draw:text-box></draw:frame></draw:g></draw:page>""")
    defer discard catch File.delete(path)
    let presentation = expect Odp.load(path)
    let page         = &presentation.slides[0]
    Swag.require(page.simplified and Utf8.contains(page.title, "hidden"))
    Swag.require(Utf8.contains(page.canvasHtml(960, 720), "Still readable"))
}

// Malformed XML, missing pages and encrypted content fail with a typed readable error.
#test
{
    for body in ["<draw:page><draw:frame>", ""]
    {
        let path = odpTestPackage(body)
        defer discard catch File.delete(path)
        var error: Swag.Error
        discard catch Odp.load(path) as error
        Swag.require(error.value() is Errors.InvalidFormatError)
    }

    let path = odpTestPackage("<draw:page draw:name='Encrypted'/>", manifest: "<manifest><encryption-data/></manifest>")
    defer discard catch File.delete(path)
    var error: Swag.Error
    discard catch Odp.load(path) as error
    Swag.require(error.value() is Errors.UnsupportedFormatError)
}

// A slide can explicitly hide the master's static objects and background.
#test
{
    let styles = "<styles><style name='Hide' family='drawing-page'><drawing-page-properties background-objects-visible='false' background-visible='false'/></style><style name='Paper' family='drawing-page'><drawing-page-properties fill='solid' fill-color='#216a56'/></style><master-page name='Master' style-name='Paper'><rect x='0in' y='0in' width='1in' height='1in'/></master-page></styles>"
    let path   = odpTestPackage("<draw:page draw:name='Visible body' draw:master-page-name='Master' draw:style-name='Hide'><draw:frame svg:x='0in' svg:y='0in' svg:width='4in' svg:height='1in'><draw:text-box><text:p>Body</text:p></draw:text-box></draw:frame></draw:page>", styles)
    defer discard catch File.delete(path)
    let presentation = expect Odp.load(path)
    Swag.require(presentation.slides[0].shapes.count == 1 and presentation.slides[0].background == "FFFFFF")
}

// Changing a saved paint color does not re-enable an inherited no-fill or no-stroke mode.
#test
{
    let styles = "<styles><style name='None' family='graphic'><graphic-properties fill='none' stroke='none' fill-color='#216a56' stroke-color='#216a56'/></style><style name='Color' family='graphic' parent-style-name='None'><graphic-properties fill-color='#234567' stroke-color='#234567'/></style></styles>"
    let path   = odpTestPackage("<draw:page draw:name='No paint'><draw:frame draw:style-name='Color' svg:x='0in' svg:y='0in' svg:width='4in' svg:height='1in'><draw:text-box><text:p>Clear background</text:p></draw:text-box></draw:frame></draw:page>", styles)
    defer discard catch File.delete(path)
    let presentation = expect Odp.load(path)
    Swag.require(presentation.slides[0].shapes[0].fill.isEmpty() and presentation.slides[0].shapes[0].line.isEmpty())
}
