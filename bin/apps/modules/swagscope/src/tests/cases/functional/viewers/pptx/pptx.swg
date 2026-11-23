#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

// Supported presentation packages select the slide reader by suffix.
#test
{
    let registry = createViewerPluginRegistry()
    for fileName in ["deck.pptx", "deck.ppsx", "deck.pptm"]
    {
        let choices = registry.choices(fileName)
        Swag.require(choices.count and choices[0].key == "pptx")
        Swag.require(registry.explicitlySupports(fileName))
    }

    for extension in [".ppt", ".pps", ".pot", ".potx", ".potm"]
    {
        let fileName = Format.toString("deck%", extension)
        let choices  = registry.choices(fileName)
        Swag.require(choices.count and choices[0].key == "pptx")
        Swag.require(registry.explicitlySupports(fileName))
    }
}

// Legacy presentations and templates receive specific read-only format errors.
#test
{
    for extension in [".ppt", ".pps"]
    {
        var loadError: Swag.Error
        discard catch Pptx.loadPresentationFile(Format.toString("deck%", extension)) as loadError
        Swag.require(loadError.value() is Errors.UnsupportedFormatError)
        Swag.require(Errors.message(loadError.value()) == Pptx.texts().err_LegacyFormat)
    }

    for extension in [".pot", ".potx", ".potm"]
    {
        var loadError: Swag.Error
        discard catch Pptx.loadPresentationFile(Format.toString("template%", extension)) as loadError
        Swag.require(loadError.value() is Errors.UnsupportedFormatError)
        Swag.require(Errors.message(loadError.value()) == Pptx.texts().err_TemplateFormat)
    }
}

// The declared slide list, not ZIP member order, determines the reading sequence.
#test
{
    let presentation = expect Pptx.Presentation.load(scopeTestDataPath("viewer.slides.pptx"))
    Swag.require(presentation.slides.count == 2 and presentation.omittedImages == 1)
    Swag.require(Utf8.contains(presentation.slides[0].readingHtml(), "Opens first"))
    Swag.require(Utf8.contains(presentation.slides[1].readingHtml(), "First &amp; final"))
    Swag.require(Utf8.contains(presentation.slides[0].readingHtml(), "[Image not shown]"))
}

// A presentation opens in its reading viewer before the ZIP fallback.
#test
{
    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.pptx"), true)
    Swag.require(window.choices[window.activeChoiceIndex].key == "pptx")
    let view = assume cast(*Pptx.Panel, window.instances[window.activeChoiceIndex].view)
    Swag.require(view.view != null and view.presentation.slides.count == 1)
    Swag.require(not window.viewerBar.isLocallyVisible() and window.documentPanel.margin.w == 0)
}

// Macro-free PowerPoint Slide Show packages use the same inert, read-only slide reader.
#test
{
    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.ppsx"), true)
    Swag.require(window.choices[window.activeChoiceIndex].key == "pptx")
    let view = assume cast(*Pptx.Panel, window.instances[window.activeChoiceIndex].view)
    Swag.require(view.presentation.slides.count == 1)
    Swag.require(Utf8.contains(view.presentation.slides[0].readingHtml(), "Read-only slideshow"))
}

// A macro-enabled package exposes slides to the static reader while its VBA part remains inert.
#test
{
    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.macros.pptm"), true)
    Swag.require(window.choices[window.activeChoiceIndex].key == "pptx")
    let view = assume cast(*Pptx.Panel, window.instances[window.activeChoiceIndex].view)
    Swag.require(view.presentation.slides.count == 1)
    Swag.require(Utf8.contains(view.presentation.slides[0].readingHtml(), "Macro stays inert"))
}

// A bounded slide overview shows available previews and tracks slide navigation.
#test
{
    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.geometry.pptx"), false)
    let view   = assume cast(*Pptx.Panel, window.currentView)
    Swag.require(not view.gallery.isVisible())
    view.openPages()
    host.paint(window)
    Swag.require(view.gallery.isVisible() and view.previews[0].contentTarget and view.previews[1].contentTarget)
    view.showSlide(1)
    Swag.require(view.slide == 1 and view.navigation.currentPage == 1)
    Swag.require(view.slideLabel.text() == "2 / 2" and not Utf8.contains(window.readingLine.details.text(), "2 of 2"))
}

// An embedded slide picture appears inline in the declared slide order.
#test
{
    let presentation = expect Pptx.Presentation.load(scopeTestDataPath("viewer.pictures.pptx"))
    Swag.require(presentation.slides.count == 2 and presentation.omittedImages == 0)
    let first = presentation.slides[0].readingHtml()
    Swag.require(Utf8.indexOf(first, "Opens first") < Utf8.indexOf(first, "data:image/jpeg;base64,"))
    Swag.require(Utf8.contains(presentation.slides[1].readingHtml(), "First &amp; final"))
    Swag.require(Utf8.contains(first, "width=\"320\" height=\"240\""))
    Swag.require(Utf8.contains(first, "alt=\"Grey &amp; silver arcs\""))
}

// Direct run styling and paragraph alignment survive the slide reading projection.
#test
{
    let presentation = expect Pptx.Presentation.load(scopeTestDataPath("viewer.formatted.pptx"))
    Swag.require(presentation.slides.count == 2 and presentation.omittedImages == 0)
    Swag.require(Utf8.contains(presentation.slides[0].readingHtml(),
                               "<p style=\"text-align:center\"><b>Opens first</b><i> styled</i></p>"))
    Swag.require(Utf8.contains(presentation.slides[1].readingHtml(),
                               "<p style=\"text-align:right\">First &amp; final</p>"))
}

// A PowerPoint deck from the Apache POI corpus keeps the slide sequence and text.
#test
{
    let presentation = expect Pptx.Presentation.load(scopeTestDataPath("viewer.poi-sample.pptx"))
    Swag.require(presentation.slides.count == 2)
    Swag.require(Utf8.contains(presentation.slides[0].readingHtml(), "Title of the first slide"))
    Swag.require(Utf8.contains(presentation.slides[1].readingHtml(), "This is the second slide"))
}

// Missing presentation relationships cannot silently become an empty deck.
#test
{
    var loadError: Swag.Error
    discard catch Pptx.Presentation.load(scopeTestDataPath("viewer.damaged.pptx")) as loadError
    Swag.require(loadError.value() is Errors.InvalidFormatError)
}

// A deck of untitled slides has a visual index. Browsing it leaves the slide and the
// reading mode alone until a thumbnail is chosen, in either palette and layout.
#test
{
    func addPart(entries: *Array'ZipFixtureEntry, name, source: string)
    {
        var entry: ZipFixtureEntry
        entry.name = name
        entry.plain.add(cast(const [..] u8, source))
        entry.packed = entry.plain
        entries.add(entry)
    }

    let file = Testing.tempFilePath("scope-slide-gallery-", ".pptx")
    defer discard catch File.delete(file)
    var entries: Array'ZipFixtureEntry
    var source: String = "<p:presentation><p:sldIdLst>"
    for i in 36 do
        source += Format.toString("<p:sldId id=\"%\" r:id=\"rId1\"/>", 256 + i)
    source += "</p:sldIdLst></p:presentation>"
    addPart(&entries, "ppt/presentation.xml", source)
    addPart(&entries, "ppt/_rels/presentation.xml.rels", """<Relationships><Relationship Id="rId1" Type="relationships/slide" Target="slides/blank.xml"/></Relationships>""")
    addPart(&entries, "ppt/slides/blank.xml", "<p:sld><p:cSld><p:spTree/></p:cSld></p:sld>")
    discard expect File.writeAllBytes(file, buildZipEntries(entries.toSlice()).toSlice())

    for light in [false, true]
    {
        for grid in [false, true]
        {
            var host: HeadlessHost
            let workspace = testWorkspace(&host, light: light)
            defer host.shutdown()
            var window = workspace.primary
            var other: *Pptx.Panel?
            if grid
            {
                workspace.openScene([file, scopeTestDataPath("viewer.geometry.pptx")], .Grid2)
                openViews(&host, workspace)
                let scene = unwrap workspace.scene()
                window = unwrap scene.views[0].document
                other = assume cast(*Pptx.Panel, scene.views[1].document!.currentView)
            }
            else
            {
                window.openFile(file, remember: false)
                completeQueuedViewerFile(&host, window)
            }

            let deck = assume cast(*Pptx.Panel, window.currentView)
            Swag.require(deck.presentation.slides.count == 36 and not deck.gallery.isVisible())
            deck.showNotes()
            host.click(deck.view!.surfaceRect().center())
            host.shortcut(.O, .Control | .Shift)
            Swag.require(deck.gallery.isVisible() and not deck.navigationMode.isVisible())
            Swag.require(deck.thumbnailScroll.position.y == deck.outlinePanel.parent!.paddedClientRect().y)
            Swag.require(deck.thumbnailScroll.surfaceRect().y <= window.documentPanel.surfaceRect().y + window.themeMetrics().floating_Inset)
            let reading = deck.view.position
            host.mouseWheel(deck.gallery.surfaceRect().center(), -6)
            host.settleAnimations(&host.surfaceWnd)
            Swag.require(deck.gallery.scrollPos.y > 0 and deck.slide == 0 and deck.notesMode and deck.view.position == reading)
            let range = deck.gallery.visibleRange()
            let index = range.first + deck.gallery.columns
            host.click(deck.gallery.localToSurface(deck.gallery.cellRect(index).center() - deck.gallery.scrollPos))
            Swag.require(deck.slide == index and deck.notesMode)
            host.keyPress(.End)
            Swag.require(deck.slide == 35 and deck.gallery.visibleRange().end == 36)
            host.paint(&host.surfaceWnd)
            Swag.require(deck.previews[35].contentTarget and not deck.previews[0].contentTarget)
            host.shortcut(.O, .Control | .Shift)
            Swag.require(not deck.gallery.isVisible() and deck.slide == 35)
            if other do
                Swag.require(other.slide == 0 and not other.gallery.isVisible())
        }
    }
}
