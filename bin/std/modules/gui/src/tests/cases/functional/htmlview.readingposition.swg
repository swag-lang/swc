#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

func readingPositionText()->String
{
    var result: String = "<html><body><h1>A reading position</h1><p>"
    for 500 do
        result += "A long paragraph keeps words together while typography and width change. "
    result += "</p><p>After the paragraph.</p></body></html>"
    return result
}

func assertReadingPassage(view: *HtmlView, position: HtmlReadingPosition)
{
    var found = false
    for box in view.layout.boxes
    {
        for item in box.items where item.kind == .Text and
                                    item.node != HtmlNoNode and
                                    item.sourceStart <= position.textOffset and
                                    item.sourceEnd > position.textOffset
        {
            if view.document.constNode(item.node).sourceOffset != position.sourceOffset do
                continue
            let expected = item.y + Math.max(item.ascent + item.descent, 1) * position.lineFraction
            Swag.require(Math.abs(view.scroll.scrollPosition().y - expected) < 1)
            found = true
        }
    }

    Swag.require(found)
}

// Long paragraphs retain their exact text passage across font-size and reading-column changes.
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 500)
    let view = HtmlView.createText(&host.root, readingPositionText())
    view.resize(900, 500)
    view.scroll.setScrollPos(0, 950)
    let passage = view.readingPosition()
    Swag.require(passage.isValid() and not passage.atStart and passage.textOffset > 0)
    let before = view.scroll.scrollPosition().y
    var style  = HtmlStyle.theme()
    style.bodyFontSize    = 25
    style.maxContentWidth = 520
    view.setDocumentStyle(style)
    Swag.require(view.restoreReadingPosition(passage))
    assertReadingPassage(view, passage)
    Swag.require(Math.abs(view.scroll.scrollPosition().y - before) > 200)
    style.bodyFontSize    = 16
    style.maxContentWidth = 840
    view.setDocumentStyle(style)
    Swag.require(view.restoreReadingPosition(passage))
    assertReadingPassage(view, passage)
}

// Default/empty positions do not scroll; restoring the top retains leading whitespace exactly.
#test
{
    var host: Testing.HeadlessHost
    host.setup(700, 400)
    let view = HtmlView.createText(&host.root, readingPositionText())
    view.resize(700, 400)
    let top = view.readingPosition()
    Swag.require(top.isValid() and top.atStart)
    view.scroll.setScrollPos(0, 600)
    let before = view.scroll.scrollPosition()
    Swag.require(not view.restoreReadingPosition({}) and view.scroll.scrollPosition() == before)
    Swag.require(view.restoreReadingPosition(top) and view.scroll.scrollPosition().y == 0)
    let empty = HtmlView.createText(&host.root, "<html><body></body></html>")
    empty.resize(700, 400)
    Swag.require(not empty.readingPosition().isValid())
}

// A position can restore an unchanged source in a fresh view, including Unicode and entities.
#test
{
    var source: String = "<html><body>"
    for index in 80 do
        source += Format.toString("<p>Passage % — Un café &amp; une pensée. <b>Continue reading.</b></p>", index)
    source += "</body></html>"
    var host: Testing.HeadlessHost
    host.setup(760, 450)
    let first = HtmlView.createText(&host.root, source)
    first.resize(760, 450)
    first.scroll.setScrollPos(0, 1600)
    let passage = first.readingPosition()
    Swag.require(passage.isValid())
    first.destroy()
    let second = HtmlView.createText(&host.root, source)
    second.resize(580, 450)
    Swag.require(second.restoreReadingPosition(passage))
    assertReadingPassage(second, passage)
}

// An image/gap-only viewport has no passage; capturing it must not jump to text below the screen.
#test
{
    var host: Testing.HeadlessHost
    host.setup(700, 400)
    let view = HtmlView.createText(&host.root, "<html><body><div style='height:1000px'></div><p>Below the visible area.</p></body></html>")
    view.resize(700, 400)
    view.scroll.setScrollPos(0, 200)
    Swag.require(not view.readingPosition().isValid())
}

// A fixed header's nested text and independently scrolled panels cannot become a book passage.
#test
{
    var host: Testing.HeadlessHost
    host.setup(700, 400)
    let view = HtmlView.createText(&host.root, "<html><body><header style='position:fixed;top:0'><p>Fixed navigation</p></header><div style='height:180px;overflow:auto'><p>Independent panel</p><div style='height:900px'></div></div><div style='height:1000px'></div></body></html>")
    view.resize(700, 400)
    Swag.require(not view.readingPosition().isValid())
}
