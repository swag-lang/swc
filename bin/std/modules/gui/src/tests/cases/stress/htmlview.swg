#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

// A search over a streamed document lands on the box that draws the match, wherever it is in the
// file and however much of it has been read.
#[Swag.TestTag("stress")]
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("gui_html_stream_%.html", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    let fixture       = expect File.readAllText(htmlFixturePath())
    let query         = "distant html verification marker"
    let fixtureOffset = Utf8.indexOf(fixture.toString(), query)
    Swag.assert(fixtureOffset != Swag.U64.Max)

    var source: String = "<html><body>"
    for 24_000 do
        source += "<h2>Streamed section</h2><p>A paragraph stays outside the resident window.</p>"
    let offset = source.length + fixtureOffset
    source += fixture
    for 5_000 do
        source += "<p>A trailing paragraph keeps the document large.</p>"
    source += "</body></html>"
    Swag.assert(source.length >= 2 * 1024 * 1024)
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(960, 680)

    let view = HtmlView.createFile(&host.root, fileName)
    view.resize(960, 680)
    view.applyLayout()
    let revealed = view.revealFileOffset(offset, query)
    Swag.assert(revealed)

    var steps = 0'u32
    while view.isLoading() and steps < 4_000
    {
        view.streamStep()
        steps += 1
    }

    Swag.assert(not view.isLoading())
    Swag.assert(view.pendingSearch.isEmpty())
    Swag.assert(view.searchNode != HtmlNoNode)
    Swag.assert(Utf8.contains(view.document.textOf(view.searchNode), query))
    Swag.assert(view.searchEnd - view.searchStart == query.count)

    // The match is what the viewport shows, not an estimate of where it might be.
    let box = view.boxOfNode(view.searchNode)
    Swag.assert(box != HtmlNoNode)
    let top      = view.layout.constBox(box).rect.y + (view.virtualSource ? view.virtualOrigin : 0)
    let position = view.scroll.scrollPosition().y
    Swag.assert(top >= position and top <= position + view.scroll.paddedClientRect().height)
}

// Progressive refreshes spread out fourfold, so a large generated page does not repeatedly
// rebuild almost the same prefix while the reader is still interacting with it.
#[Swag.TestTag("stress")]
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("gui_html_refresh_%.html", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String = "<style>pre { color: #102030 }</style><pre>"
    for 2_400 do
        source += "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ repeated source line\n"
    source += "</pre>"
    Swag.assert(source.length > 192 * 1024)
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(640, 360)

    let view = HtmlView.createFile(&host.root, fileName)
    view.resize(640, 360)
    view.applyLayout()
    let firstParseCount = view.sheet.parseCount
    Swag.assert(firstParseCount == 1)
    while view.bytesRead < 192 * 1024 do
        view.streamStep()

    Swag.assert(view.nextRefresh == view.bytesRead * 4)
    Swag.assert(view.sheet.parseCount == firstParseCount)
    view.rebuild()
    Swag.assert(view.sheet.parseCount == firstParseCount)
    view.stopLoading()
}

// A real generated Rustdoc page keeps its full production scale. Its highlighted source expands
// to hundreds of thousands of nodes, and its structural selectors used to rescan tens of
// thousands of siblings for each match. Small documents cannot expose that failure mode.
#[Swag.TestTag("stress")]
#test
{
    let allocator = Swag.defaultAllocator()
    let initial   = allocator.stats()

    var host: Testing.HeadlessHost
    host.setup(960, 680)

    let path = guiFixturePath("html.rustdoc-large.html")
    let view = HtmlView.createFile(&host.root, path)
    view.resize(960, 680)
    view.applyLayout()

    Swag.assert(view.fileSize == 8_153_570)
    Swag.assert(view.virtualSource)
    Swag.assert(view.sourceDone)
    Swag.assert(view.virtualWindowEnd - view.virtualWindowStart < 256 * 1024)
    Swag.assert(view.document.nodes.count < 20_000)
    Swag.assert(view.layout.boxes.count < 10_000)
    Swag.assert(view.layout.styles.count < 10_000)
    Swag.assert(view.virtualHeight > view.layout.documentHeight * 10)

    // Visiting the middle replaces the resident document instead of appending to it. Returning
    // to the same source offset materializes the same bounded window and the same pixels.
    let middle   = view.fileSize / 2
    var revealed = view.revealFileOffset(middle, "")
    Swag.assert(revealed)
    let middleStart = view.virtualWindowStart
    let middleEnd   = view.virtualWindowEnd
    let first       = Hash.hashBytes32(host.render(view).pixels.toSlice())
    Swag.assert(middleStart < middle and middleEnd > middle)
    Swag.assert(middle - middleStart > (middleEnd - middleStart) / 4)
    Swag.assert(middleEnd - middle > (middleEnd - middleStart) / 4)
    Swag.assert(not view.virtualPendingSeek)
    Swag.assert(view.document.nodes.count < 20_000)

    revealed = view.revealFileOffset(view.virtualContentStart, "")
    Swag.assert(revealed)
    revealed = view.revealFileOffset(middle, "")
    Swag.assert(revealed)
    Swag.assert(view.virtualWindowStart == middleStart and view.virtualWindowEnd == middleEnd)
    let second = Hash.hashBytes32(host.render(view).pixels.toSlice())
    Swag.assert(second == first)

    let resident = allocator.stats()
    Swag.assert(resident.sizeAlloc < initial.sizeAlloc + 128 * 1024 * 1024)
}

// Large ordinary HTML is bounded too, even when it has no generated-source `<pre>` shape. The
// generic window may start at a recovery boundary, but it must never make file size become DOM
// size and revisiting one byte offset must choose the same resident source.
#[Swag.TestTag("stress")]
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("gui_html_large_window_%.html", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String = "<html><head><style>p { margin: 4px }</style></head><body>"
    for index in 28_000 do
        source += Format.toString("<p id='row-%'>Paragraph % carries enough ordinary HTML to exercise a generic resident window.</p>\n", index, index)
    source += "</body></html>"
    Swag.assert(source.length > 2 * 1024 * 1024)
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(720, 480)

    let view = HtmlView.createFile(&host.root, fileName)
    view.resize(720, 480)
    view.applyLayout()
    Swag.assert(view.virtualSource and not view.virtualPreformatted)
    Swag.assert(view.document.nodes.count < 20_000)

    let middle   = view.fileSize / 2
    var revealed = view.revealFileOffset(middle, "")
    Swag.assert(revealed)
    let residentStart = view.virtualWindowStart
    let residentEnd   = view.virtualWindowEnd
    Swag.assert(residentStart < middle and residentEnd > middle)
    Swag.assert(view.document.nodes.count < 20_000)
    revealed = view.revealFileOffset(view.virtualContentStart, "")
    Swag.assert(revealed)
    revealed = view.revealFileOffset(middle, "")
    Swag.assert(revealed)
    Swag.assert(view.virtualWindowStart == residentStart and view.virtualWindowEnd == residentEnd)
}

// A virtual HTML document follows the latest scrollbar position through repeated long seeks and
// reversals. Revisiting a stop must materialize the same source window and the same pixels.
#[Swag.TestTag("stress")]
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("gui_html_virtual_scrub_%.html", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String = "<html><body><style>p { margin: 4px } h2 { color: #2255aa }</style>"
    for index in 32_000 do
        source += Format.toString("<h2>Scrub section %</h2><p>Unique paragraph % keeps a virtual seek visible and deterministic.</p>\n", index, index)
    source += "</body></html>"
    Swag.assert(source.length > 2 * 1024 * 1024)
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(720, 480)
    let view = HtmlView.createFile(&host.root, fileName)
    view.resize(720, 480)
    view.applyLayout()
    Swag.assert(view.virtualSource and view.virtualHeight > 0)

    // Returning to the resident window before the timer fires cancels the obsolete long seek.
    let residentY = view.scroll.scrollPosition().y
    view.scroll.setScrollPos(0, view.virtualHeight * 0.85)
    Swag.assert(view.virtualPendingSeek)
    view.scroll.setScrollPos(0, residentY)
    Swag.assert(not view.virtualPendingSeek)

    // Two gestures before the timer fires coalesce to the newest request.
    view.scroll.setScrollPos(0, view.virtualHeight * 0.85)
    view.scroll.setScrollPos(0, view.virtualHeight * 0.15)
    Swag.assert(view.virtualPendingSeek and view.loadTimer != null)
    host.fireTimer(view.loadTimer)
    let lowOffset = view.virtualContentStart + cast(u64, (0.15 * cast(f32, (view.fileSize - view.virtualContentStart))))
    Swag.assert(view.virtualWindowStart <= lowOffset and view.virtualWindowEnd >= lowOffset)
    Swag.assert(not view.virtualPendingSeek)

    let ratios = [0.15'f32, 0.75'f32, 0.35'f32, 0.9'f32]
    var firstPass: [4] u32
    for ratio, index in ratios
    {
        view.scroll.setScrollPos(0, view.virtualHeight * ratio)
        var image = host.render(view)
        Swag.assert(not view.virtualPendingSeek)
        Swag.assert(view.layout.boxes.count > 1)
        firstPass[index] = Hash.hashBytes32(image.pixels.toSlice())
    }

    for index in ratios.count
    {
        let reverse = ratios.count - index - 1
        view.scroll.setScrollPos(0, view.virtualHeight * ratios[reverse])
        var image = host.render(view)
        Swag.assert(not view.virtualPendingSeek)
        Swag.assert(Hash.hashBytes32(image.pixels.toSlice()) == firstPass[reverse])
    }
}

// A hostile document nested thousands of elements deep flattens at the depth bound instead of
// walking the recursive passes off the native stack, and its content stays readable.
#[Swag.TestTag("stress")]
#test
{
    var source: String
    for 4000 do
        source += "<div>"
    source += "deep text"

    let document = parseDocument(source.toString())
    Swag.assert(Utf8.contains(document.textContent(0).toString(), "deep text"))

    var deepest = 0'u64
    for index in document.nodes.count
    {
        var depth = 0'u64
        var walk  = document.constNode(cast(u32, index)).parent
        while walk != HtmlNoNode
        {
            depth += 1
            walk  = document.constNode(walk).parent
        }

        deepest = Math.max(deepest, depth)
    }

    Swag.assert(deepest <= HtmlMaxElementDepth + 1)

    // The whole pipeline survives the same document: styling, box building, layout, painting.
    var host: Testing.HeadlessHost
    host.setup(320, 240)

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(320, 240)
    view.applyLayout()
    view.rebuild()
    discard host.render(view)
    Swag.assert(Utf8.contains(view.document.textContent(0).toString(), "deep text"))
}
