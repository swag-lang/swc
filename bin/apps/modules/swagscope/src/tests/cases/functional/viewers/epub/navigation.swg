#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

// EPUB 2 and EPUB 3 expose the same authored titles, nesting, order and fragment destinations.
#test
{
    for name in ["viewer.navigation.epub", "viewer.navigation.ncx.epub"]
    {
        let book = expect Epub.Book.load(scopeTestDataPath(name))
        Swag.require(book.navigation.failure.isEmpty())
        Swag.require(book.navigation.entries.count == 3)
        let entries = book.navigation.entries.toSlice()
        Swag.require(entries[0].title == "First & foremost" and entries[0].chapter == 0)
        Swag.require(entries[1].title == "A quiet passage" and entries[1].level == 2)
        Swag.require(entries[1].chapter == 0 and entries[1].fragment == "passage")
        Swag.require(entries[2].chapter == 1 and entries[2].fragment == "arrival")
    }
}

// The real Gutenberg publication's navigation is usable, including nested sections.
#test
{
    let book = expect Epub.Book.load(scopeTestDataPath("viewer.christmas-carol.epub"))
    Swag.require(book.navigation.failure.isEmpty())
    var linked = 0'u64
    var nested = 0'u64
    for entry in book.navigation.entries
    {
        if entry.chapter != Swag.U64.Max do
            linked += 1
        if entry.level > 1 do
            nested += 1
    }

    Swag.require(linked > 10 and nested > 0)
}

// Encoded Unicode and spaces are decoded without permitting a URL to leave the package.
#test
{
    let entry = Epub.NavigationEntry.resolve("OPS/nav/toc.xhtml", "../chapters/part%20one.xhtml#caf%C3%A9")
    Swag.require(entry.path == "OPS/chapters/part one.xhtml" and entry.fragment == "café")
    let same = Epub.NavigationEntry.resolve("OPS/part.xhtml", "#end")
    Swag.require(same.path == "OPS/part.xhtml" and same.fragment == "end")
    let punctuated = Epub.NavigationEntry.resolve("OPS/part.xhtml", "#section:part")
    Swag.require(punctuated.path == "OPS/part.xhtml" and punctuated.fragment == "section:part")
    for reference in ["https://example.org/a", "file:///tmp/private", "//host/a", "../../../secret",
                      "../%2e%2e/../secret", "%2fetc/passwd", "%5csecret", "%66ile:secret", "bad%QQ"]
    {
        let blocked = Epub.NavigationEntry.resolve("OPS/nav.xhtml", reference)
        Swag.require(blocked.path.isEmpty())
    }
}

// Only the table of contents is collected; landmarks and scripts cannot add destinations.
#test
{
    let source     = """<html><body><nav epub:type="landmarks"><a href="a.xhtml">Landmark</a></nav>
                    <nav epub:type="toc"><ol><li><a href="one.xhtml">One <span>chapter</span></a></li></ol></nav>
                    <script>ignored</script></body></html>"""
    let navigation = expect Epub.Navigation.parse(source, "OPS/nav.xhtml", false)
    Swag.require(navigation.entries.count == 1 and navigation.entries[0].title == "One chapter")
}

// Broken navigation and external entities cannot start an unbounded or external parse.
#test
{
    for source in ["<nav epub:type=\"toc\"><ol>", "<html><body></div></html>", "<!DOCTYPE html [<!ENTITY x SYSTEM 'file:///tmp/secret'>]><html/>"]
    {
        var error: Swag.Error
        discard catch Epub.Navigation.parse(source, "OPS/nav.xhtml", false) as error
        Swag.require(error.value() is Errors.InvalidFormatError)
    }

    var nested: String
    for 65 do
        nested += "<div>"
    var error: Swag.Error
    discard catch Epub.Navigation.parse(nested, "OPS/nav.xhtml", false) as error
    Swag.require(error.value() is Errors.UnsupportedFormatError)
}

// A table-of-contents selection can reach a passage in the current or another chapter.
#test
{
    var host: HeadlessHost
    let window = openFramedViewerWindow(&host, scopeTestDataPath("viewer.navigation.epub"), true)
    let view   = assume cast(*Epub.Panel, window.currentView)
    Swag.require(view.contents.count == 3 and view.outline.headings.count == 3)
    view.selectContents(2)
    completeQueuedViewerFile(&host, window)
    Swag.require(view.chapter == 1 and view.chapterLabel.text() == "2 / 2")
    Swag.require(view.view != null)
    view.selectContents(1)
    completeQueuedViewerFile(&host, window)
    Swag.require(view.chapter == 0)
    Swag.require(view.outline.headings[1].level == 2)
    view.outline.setFilter("second")
    Swag.require(view.outline.rows.count == 1)
    view.selectContents(99)
    Swag.require(view.chapter == 0)
}

// The contents mark the entry being read from the start, and follow passages, links and turns:
// an entry whose passage is above the text being read is behind the reader.
#test
{
    var host: HeadlessHost
    let window = openFramedViewerWindow(&host, scopeTestDataPath("viewer.navigation.epub"), false)
    let view   = assume cast(*Epub.Panel, window.currentView)
    var chosen = 0
    view.outline.sigSelected += func|&chosen|(_, _) { chosen += 1 }
    Swag.require(view.outline.markedTarget() == 0)

    view.followLink("one.xhtml#passage")
    completeQueuedViewerFile(&host, window)
    Swag.require(view.chapter == 0 and view.outline.markedTarget() == 1)

    // The second chapter's only entry is a passage further down: its start still reads the first.
    view.turn(1)
    completeQueuedViewerFile(&host, window)
    Swag.require(view.chapter == 1 and view.outline.markedTarget() == 1)
    view.followLink("two.xhtml#arrival")
    completeQueuedViewerFile(&host, window)
    Swag.require(view.outline.markedTarget() == 2)

    view.turn(-1)
    completeQueuedViewerFile(&host, window)
    Swag.require(view.chapter == 0 and view.outline.markedTarget() == 0 and chosen == 0)
}

// A closed outline does not follow the chapter as it scrolls; it marks the entry in view as it
// opens again, and follows the scroll while open.
#test
{
    var host: HeadlessHost
    let window  = openFramedViewerWindow(&host, scopeTestDataPath("viewer.navigation.epub"), true)
    let view    = assume cast(*Epub.Panel, window.currentView)
    let outline = view.outline
    view.followLink("one.xhtml#passage")
    completeQueuedViewerFile(&host, window)
    Swag.require(outline.markedTarget() == 1)

    let chapter = unwrap view.view
    Swag.require(chapter.navigateToFragment("#"))
    Swag.require(outline.markedTarget() == 1)
    outline.toggle.setChecked(true)
    outline.toggle.sigCheckedChanged.call(outline.toggle)
    Swag.require(outline.markedTarget() == 0)

    Swag.require(chapter.navigateToFragment("#passage"))
    Swag.require(outline.markedTarget() == 1)
}

// Book-owned link navigation updates the chapter counter and keeps external targets local.
#test
{
    var host: HeadlessHost
    let window = openFramedViewerWindow(&host, scopeTestDataPath("viewer.navigation.epub"), false)
    let view   = assume cast(*Epub.Panel, window.currentView)
    view.followLink("two.xhtml#arrival")
    completeQueuedViewerFile(&host, window)
    Swag.require(view.chapter == 1)
    view.followLink("one.xhtml#passage")
    completeQueuedViewerFile(&host, window)
    Swag.require(view.chapter == 0)
    for url in ["https://example.org", "../../secret.html", "missing.xhtml"]
    {
        view.followLink(url)
        Swag.require(view.chapter == 0)
    }
}

// EPUB 2's ordinary external DOCTYPE is ignored without loading its external DTD.
#test
{
    let source     = """<?xml version="1.0"?>
                    <!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
                    <ncx><navMap><navPoint><navLabel><text>Chapter</text></navLabel><content src="one.xhtml"/></navPoint></navMap></ncx>"""
    let navigation = expect Epub.Navigation.parse(source, "OPS/toc.ncx", true)
    Swag.require(navigation.entries.count == 1 and navigation.entries[0].title == "Chapter")
}

// The lens turns to a numbered chapter and its chapter rows stop at the ends of the spine.
#test
{
    var host: HeadlessHost
    let window = openFramedViewerWindow(&host, scopeTestDataPath("viewer.navigation.epub"), true)
    let view   = assume cast(*Epub.Panel, window.currentView)
    Swag.require(view.chapter == 0 and view.book.chapters.count == 2)

    func chapterRows(window: *ViewerWindow, host: *HeadlessHost)->{previous: bool, next: bool}
    {
        var result: #returntype
        window.lens.open()
        host.finishAnimations()
        defer
        {
            window.lens.close()
            host.finishAnimations()
        }

        for section in window.lens.results.sections
        {
            for &entry in section!.entries
            {
                if entry.title == Epub.texts().ui_Previous do
                    result.previous = not entry.disabled
                elif entry.title == Epub.texts().ui_Next do
                    result.next = not entry.disabled
            }
        }

        return result
    }

    let first = chapterRows(window, &host)
    Swag.require(not first.previous and first.next)

    window.lens.open(":2")
    host.finishAnimations()
    let section = unwrap window.lens.results.sections[0]
    Swag.require(section.entries[0].title == Format.toString(appStrings().lens_GoToChapter, 2) and section.entries[0].lead == "2")
    section.entries[0].run!()
    window.lens.close()
    host.finishAnimations()
    completeQueuedViewerFile(&host, window)
    Swag.require(view.chapter == 1)

    let last = chapterRows(window, &host)
    Swag.require(last.previous and not last.next)

    window.lens.open(":3")
    host.finishAnimations()
    Swag.require(window.lens.results.sections.isEmpty())
    window.lens.close()
    host.finishAnimations()
}
