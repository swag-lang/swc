#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

// Real slide coordinates, inherited title bounds and master decoration survive package loading.
#test
{
    let deck = expect Pptx.Presentation.load(scopeTestDataPath("viewer.geometry.pptx"))
    Swag.require(deck.width == 1280 and deck.height == 720 and deck.slides.count == 2)
    let page = &deck.slides[0]
    Swag.require(not page.simplified and page.background == "FAF7F0")
    Swag.require(page.title == "A quieter reading room")
    var titles   = 0'u32
    var pictures = 0'u32
    for shape in page.shapes
    {
        if shape.isTitle()
        {
            titles += 1
            Swag.require(shape.positioned and shape.bounds == Math.Rectangle{80, 100, 1120, 100})
            Swag.require(shape.fontSize == 3200 and shape.centered)
        }

        if shape.picture
        {
            pictures += 1
            Swag.require(shape.bounds == Math.Rectangle{770, 235, 380, 285})
        }
    }

    Swag.require(titles == 1 and pictures == 1)
    let reading = page.readingHtml()
    Swag.require(Utf8.contains(reading, "NORTH / FIELD NOTES"))
    Swag.require(not Utf8.contains(reading, "Click to edit"))
    Swag.require(not Utf8.contains(reading, "font-size:") and not Utf8.contains(reading, "color:"))
    Swag.require(Utf8.contains(page.canvasHtml(deck.width, deck.height), "width:29.6875vw;height:39.5833vh"))
}

// PowerPoint-authored placeholder bounds and direct run styles work outside synthetic fixtures.
#test
{
    let deck = expect Pptx.Presentation.load(scopeTestDataPath("viewer.poi-sample.pptx"))
    Swag.require(not deck.slides[0].simplified and not deck.slides[1].simplified)
    Swag.require(deck.slides[0].title == "Title of the first slide")
    let canvas = deck.slides[0].canvasHtml(deck.width, deck.height)
    Swag.require(Utf8.contains(canvas, "color:#92D050;") and Utf8.contains(canvas, "<i>"))
    Swag.require(not Utf8.contains(deck.slides[0].readingHtml(), "font-size:"))
}

// Navigation, outline selection and text mode keep the current slide and fit authored aspect.
#test
{
    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.geometry.pptx"), false)
    let view   = assume cast(*Pptx.Panel, window.currentView)
    Swag.require(view.slide == 0 and view.outline.headings.count == 2)
    let bounds = view.view!.clientRect()
    Swag.require(Math.abs(bounds.width / bounds.height - 1280.0 / 720) < 0.01)
    var next = KeyEvent{kind: .Pressed, key: .PageDown}
    Swag.require(view.hookOnChildEvent!(view.view, &next) and view.slide == 1)
    view.turn(1)
    Swag.require(view.slide == 1 and view.slideLabel.text() == "2 / 2")
    view.showSlide(999)
    Swag.require(view.slide == 1)
    view.setTextMode(true)
    Swag.require(view.textMode and view.slide == 1 and view.view.documentStyle.followTheme)
    view.outline.list.selectLine(0)
    Swag.require(view.slide == 0 and view.textMode)
    view.setTextMode(false)
    Swag.require(not view.textMode and not view.view.documentStyle.followTheme)
    var modified = KeyEvent{kind: .Pressed, key: .PageDown, modifiers: .Alt}
    Swag.require(not view.hookOnChildEvent(view.view, &modified) and view.slide == 0)
}

// Partial local transforms inherit only missing bounds; explicit no-fill wins over a parent.
#test
{
    var theme  = Pptx.SlideTheme.defaults()
    let parent = expect Pptx.SlideShape.parse("""<p:sp><p:spPr><a:xfrm><a:off x="952500" y="190500"/><a:ext cx="1905000" cy="952500"/></a:xfrm><a:solidFill><a:schemeClr val="accent1"/></a:solidFill></p:spPr></p:sp>""", &theme)
    var child  = expect Pptx.SlideShape.parse("""<p:sp><p:spPr><a:xfrm><a:off x="0" y="0"/></a:xfrm><a:noFill/></p:spPr></p:sp>""", &theme)
    child.inherit(&parent)
    Swag.require(child.positioned and child.bounds == Math.Rectangle{0, 0, 200, 100})
    Swag.require(child.fill.isEmpty() and parent.fill == "4F81BD")
    let rotated = expect Pptx.SlideShape.parse("""<p:sp><p:spPr><a:xfrm flipH="true"/></p:spPr></p:sp>""", &theme)
    Swag.require(rotated.unsupported)
}

// Unsupported slide structures retain their reading text and are explicitly marked simplified.
#test
{
    let deck = expect Pptx.Presentation.load(scopeTestDataPath("viewer.pictures.pptx"))
    Swag.require(deck.slides[0].simplified)
    var theme = Pptx.SlideTheme.defaults()
    let page  = expect Pptx.SlidePage.parse("<p:sld><p:spTree><p:grpSp><p:graphicFrame/></p:grpSp></p:spTree></p:sld>", &theme)
    Swag.require(page.simplified)
}

// XML parts are bounded trees; unclosed tags, multiple roots, entities and excess depth fail.
#test
{
    var deep: String
    for 129 do
        deep += "<a>"
    for source in ["<a>", "<a></b>", "<a/><b/>", "<!DOCTYPE a [<!ENTITY x SYSTEM 'file:///tmp/x'>]><a/>", deep.toString()]
    {
        var entry: ZipFixtureEntry
        entry.name = "part.xml"
        entry.plain.add(source)
        entry.packed = entry.plain
        let path = tempFilePath("scope-pptx-xml-", ".zip")
        defer discard catch File.delete(path)
        var entries = [entry]
        discard expect File.writeAllBytes(path, buildZipEntries(entries[0 until entries.count]).toSlice())
        let zip    = expect Archive.Zip.load(path)
        let reader = Package.PartReader{path, &zip, "Invalid XML", "XML too large"}
        var error: Swag.Error
        discard catch reader.text("part.xml") as error
        Swag.require(error.value() is Errors.InvalidFormatError or error.value() is Errors.UnsupportedFormatError)
    }
}

// UTF-8 BOMs are accepted, while external relationships never become package destinations.
#test
{
    var entries: [2] ZipFixtureEntry
    entries[0].name = "ppt/slide.xml"
    entries[0].plain.add([0xEF'u8, 0xBB, 0xBF])
    entries[0].plain.add("<p:sld/>")
    entries[0].packed = entries[0].plain
    entries[1].name   = "ppt/_rels/slide.xml.rels"
    entries[1].plain.add("""<Relationships><Relationship Id="layout" Target="layouts/one.xml" Type="urn:test/slideLayout"/><Relationship Id="remote" Target="https://example.org/theme.xml" Type="urn:test/theme" TargetMode="External"/></Relationships>""")
    entries[1].packed = entries[1].plain
    let path = tempFilePath("scope-pptx-parts-", ".zip")
    defer discard catch File.delete(path)
    discard expect File.writeAllBytes(path, buildZipEntries(entries[0 until entries.count]).toSlice())
    let zip    = expect Archive.Zip.load(path)
    let reader = Package.PartReader{path, &zip, "Invalid XML", "XML too large"}
    Swag.require((expect reader.text("ppt/slide.xml")) == "<p:sld/>")
    let relations = expect reader.relationships("ppt/slide.xml")
    Swag.require(relations.count == 1 and relations[0].path == "ppt/layouts/one.xml")
    Swag.require(Package.relationshipPath(relations.toSlice(), "/theme").isEmpty())
}
