#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// The streamed file spans 32 resident windows plus a partial tail.
const StreamedFileSize = Hex.WindowSize * 32 + 1234'u64

// The document never holds more than one window, wherever the reader is standing.
#[Swag.TestTag("stress")]
#test
{
    let fileName = writeStreamedFile(StreamedFileSize)
    defer discard catch File.delete(fileName)
    let allocator = Swag.defaultAllocator()
    let baseline  = allocator.stats()

    var doc: Hex.Document
    defer doc.close()
    let documentOpened = doc.open(fileName)
    Swag.require(documentOpened)
    Swag.require(doc.fileSize == StreamedFileSize)

    Swag.require(doc.ensure(0, 64))
    Swag.require(doc.byteAt(5) == 5)
    Swag.require(doc.window.count <= Hex.WindowSize)

    // Refill before the visible screen reaches the edge, and retain enough overlap that a
    // reversal stays in the same window instead of alternating disk reads.
    let screen         = 1024'u64
    let approachingEnd = Hex.WindowSize - Hex.WindowAlign + screen
    Swag.require(doc.ensure(approachingEnd, screen))
    Swag.require(doc.windowStart > 0)
    let prefetchedStart = doc.windowStart
    Swag.require(doc.ensure(approachingEnd - screen, screen))
    Swag.require(doc.windowStart == prefetchedStart)
    Swag.require(doc.isResident(approachingEnd - screen) and doc.isResident(approachingEnd + screen - 1))

    let last = StreamedFileSize - 1
    Swag.require(doc.ensure(last - 31, 32))
    Swag.require(doc.byteAt(last) == cast(u8, last & 0xFF))
    Swag.require(doc.window.count <= Hex.WindowSize)
    Swag.require(doc.windowStart > 0)
    Swag.require(not doc.isResident(0))

    // A bounded read reaches anywhere without moving what is on screen.
    let windowStart = doc.windowStart
    let bytes       = doc.read(1000, 4)
    Swag.require(bytes.count == 4 and bytes[0] == 0xE8 and bytes[3] == 0xEB)
    Swag.require(doc.windowStart == windowStart)
    Swag.require(doc.read(StreamedFileSize, 16).isEmpty())

    let resident = allocator.stats()
    Swag.require(resident.sizeAlloc < baseline.sizeAlloc + 2 * 1024 * 1024)
}

// Walking a file larger than one window keeps the resident bytes bounded, and the end is one key
// away rather than one key away per page.
#[Swag.TestTag("stress")]
#test
{
    let fileName = writeStreamedFile(StreamedFileSize)
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let view = hexTestViewer(&host, fileName, 900, 560)
    Swag.require(view.grid.doc.fileSize == StreamedFileSize)
    Swag.require(view.grid.topRow == 0 and view.grid.caret == 0)
    discard host.render(view)
    Swag.require(view.grid.doc.window.count <= Hex.WindowSize)

    host.focus(view.grid)
    host.keyPress(.End, .Control)
    Swag.require(view.grid.caret == StreamedFileSize - 1)
    Swag.require(view.grid.topRow == view.grid.maxTopRow())
    discard host.render(view)
    Swag.require(view.grid.doc.window.count <= Hex.WindowSize)
    Swag.require(view.grid.doc.byteAt(view.grid.caret) == cast(u8, ((StreamedFileSize - 1) & 0xFF)))

    host.keyPress(.Home, .Control)
    Swag.require(view.grid.caret == 0 and view.grid.topRow == 0)

    // The scrollbar spans the whole file and stays inside what an f32 counts exactly.
    Swag.require(view.grid.scroll.scrollSize.y > view.grid.clientRect().height)
    Swag.require(view.grid.scroll.scrollSize.y <= Hex.ScrollSpan)
}

// The bar is a proportional control: the row it names comes back through the row count, so every
// row stays reachable in a file with more rows than the span has pixels.
#[Swag.TestTag("stress")]
#test
{
    let fileName = writeStreamedFile(StreamedFileSize)
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let view = hexTestViewer(&host, fileName, 900, 560)
    let grid = view.grid
    let span = grid.scroll.scrollSize.y

    grid.scroll.setScrollPos(0, span)
    Swag.require(grid.topRow == grid.maxTopRow())

    grid.scroll.setScrollPos(0, 0)
    Swag.require(grid.topRow == 0)

    grid.setTopRow(grid.maxTopRow() / 2)
    Swag.require(grid.scroll.scrollPosition().y > 0)
    Swag.require(grid.scroll.scrollPosition().y < span)
}
