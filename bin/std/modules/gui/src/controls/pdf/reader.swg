#global public
#global namespace Pdf

using Core

internal struct PageSource
{
    objectId:    u32
    resourcesId: u32
    mediaBoxId:  u32
    cropBoxId:   u32
    rotate:      s64
}

// One document bookmark, in depth-first reading order.
struct OutlineEntry
{
    public
    {
        title:     String                 // Owned bookmark title.
        level:     u32                    // Hierarchy depth, starting at one.
        pageIndex: u64 = Swag.U64.Max     // Zero-based destination page; Max denotes a group or an unresolved destination.
        position:  Math.Point             // Destination in displayed page points, from its top-left corner.
    }
}

// Owns a mapped PDF snapshot and decodes its pages on demand.
//
// Opening indexes the object and page trees but does not decompress page content, images, or
// fonts. Each call to [[Gui.Pdf.Reader.loadPage]] returns an independent owned page; releasing that
// page releases its decoded resources without affecting this reader.
#[Swag.Opaque, Swag.NoCopy]
struct Reader
{
    // The parser retains slices into the mapped region, so the mapping is owned for the complete
    // reader lifetime.

    internal
    {
        documentMetadata: Metadata
        sourceFileName:   String
        region:           File.MappedRegion
        parser:           PdfParser
        sources:          Array'PageSource
    }
}

impl Reader
{
    // Copies a PDF file to temporary storage, maps the copy, and indexes its pages.
    //
    // The source is released before returning, so it can be overwritten or replaced while pages
    // remain readable. Temporary disk storage lasts until the reader is released.
    // Page streams and resources are decoded only by [[Gui.Pdf.Reader.loadPage]]. Encryption and
    // embedded executable content are not supported; embedded actions are ignored rather than
    // executed.
    func open(fileName: string)->Reader fail
    {
        var file = #move try File.MappedFile.openSnapshot(fileName)
        var result: retval
        result.sourceFileName = fileName
        result.region         = #move try file.mapAll()
        result.parser.bytes   = result.region.bytes()
        try indexDocument(&result.parser, &result.documentMetadata, &result.sources)
        return result
    }

    // Returns the path the document was opened from.
    mtd const fileName()->string => .sourceFileName.toString()

    // Returns the document's descriptive fields.
    mtd const metadata()->Metadata => .documentMetadata

    // Returns the number of pages found in the page tree.
    mtd const pageCount()->u64 => .sources.count

    // Returns owned bookmarks and their local destinations without decoding page content.
    //
    // Direct destinations, named destinations, and local GoTo actions are resolved. Entries
    // without a usable local destination retain their hierarchy and have pageIndex set to Max.
    // An absent outline returns an empty array; cycles in damaged outline and name trees are ignored.
    mtd loadOutline()->Array'OutlineEntry
    {
        var result:       retval
        var names:        HashTable'(String, u32)
        var pendingNames: Array'u32
        var visitedNames: HashTable'(u32, bool)
        let catalog      = .parser.catalogId
        let firstOutline = .parser.dict(.parser.dict(catalog, "Outlines"), "First")
        if firstOutline == InvalidNode do
            return result
        pendingNames.add(.parser.dict(.parser.dict(catalog, "Names"), "Dests"))
        while pendingNames.count
        {
            let node = .parser.resolve(pendingNames.popBack())
            if node == InvalidNode or visitedNames.contains(node) do
                continue
            visitedNames[node] = true
            let pairsId = .parser.dict(node, "Names")
            if pairsId != InvalidNode and .parser.nodes[pairsId].kind == .Array
            {
                let pairs = .parser.nodes[pairsId].values
                var index = 0'u64
                while index + 1 < pairs.count
                {
                    let name = String.from(.parser.stringValue(pairs[index]))
                    names[name] = pairs[index + 1]
                    index       += 2
                }
            }

            let kidsId = .parser.dict(node, "Kids")
            if kidsId != InvalidNode and .parser.nodes[kidsId].kind == .Array
            {
                let kids = .parser.nodes[kidsId].values
                for child in kids do
                    pendingNames.add(child)
            }
        }

        var pages: HashTable'(u32, u64)
        for source, index in .sources do
            pages[source.objectId] = index
        var pending: Array'{node: u32, level: u32}
        var visited: HashTable'(u32, bool)
        pending.add({firstOutline, 1})
        while pending.count
        {
            let item = pending.popBack()
            let node = .parser.resolve(item.node)
            if node == InvalidNode or visited.contains(node) do
                continue
            visited[node] = true
            var entry: OutlineEntry
            entry.level = item.level
            let title = .parser.stringValue(.parser.dict(node, "Title"))
            if title.count >= 2 and title[0] == 0xFE and title[1] == 0xFF do
                entry.title = Text.decode(cast(const [..] u8) title[2 to], .Utf16Be)
            else do
                entry.title = Text.decode(cast(const [..] u8) title, .Windows1252)

            var destination = .parser.dict(node, "Dest")
            if destination == InvalidNode
            {
                let action = .parser.dict(node, "A")
                if .parser.name(.parser.dict(action, "S")) == "GoTo" do
                    destination = .parser.dict(action, "D")
            }

            var resolved: HashTable'(u32, bool)
            while destination != InvalidNode and not resolved.contains(destination)
            {
                resolved[destination] = true
                let kind = .parser.nodes[destination].kind
                if kind == .Array do
                    break
                if kind == .Dictionary do
                    destination = .parser.dict(destination, "D")
                elif kind == .Name or kind == .String
                {
                    let name  = .parser.nodes[destination].text
                    let found = names.tryFind(name)
                    destination = found ? .parser.resolve(found.value) : .parser.dict(.parser.dict(catalog, "Dests"), name.toString())
                }
                else do
                    destination = InvalidNode
            }

            if destination != InvalidNode and .parser.nodes[destination].kind == .Array
            {
                let values = .parser.nodes[destination].values
                if values.count >= 2
                {
                    let page = pages.tryFind(.parser.resolve(values[0]))
                    if page
                    {
                        entry.pageIndex = page.value
                        let source = .sources[page.value]
                        let region = catch pageBox(&.parser, source.objectId, source.mediaBoxId, source.cropBoxId, source.rotate) as boxError
                        if boxError == null
                        {
                            let mode = String.from(.parser.name(values[1]))
                            var x    = region.box.x
                            var y    = region.box.bottom()
                            if (mode == "XYZ" or mode == "FitV" or mode == "FitBV" or mode == "FitR") and values.count > 2 do
                                x = cast(f32) .parser.number(values[2], x)
                            if mode == "XYZ" and values.count > 3 do
                                y = cast(f32) .parser.number(values[3], y)
                            elif (mode == "FitH" or mode == "FitBH") and values.count > 2 do
                                y = cast(f32) .parser.number(values[2], y)
                            elif mode == "FitR" and values.count > 5 do
                                y = cast(f32) .parser.number(values[5], y)
                            x -= region.box.x
                            y -= region.box.y
                            switch region.rotate
                            {
                            case 90:  entry.position = {y, x}
                            case 180: entry.position = {region.box.width - x, y}
                            case 270: entry.position = {region.box.height - y, region.box.width - x}
                            default:  entry.position = {x, region.box.height - y}
                            }

                            if mode == "Fit" or mode == "FitB" do
                                entry.position = {}
                        }
                    }
                }
            }

            if not entry.title.isEmpty() do
                result.add(#move entry)
            let next  = .parser.dict(node, "Next")
            let first = .parser.dict(node, "First")
            if next != InvalidNode do
                pending.add({next, item.level})
            if first != InvalidNode do
                pending.add({first, item.level + 1})
        }

        return result
    }

    // Decodes and returns the page at zero-based `index`.
    //
    // The returned page owns all content it retains and remains valid after this reader is
    // released. An out-of-range index reports [[Core.Errors.BadParameterError]].
    mtd loadPage(index: u64)->Page fail
    {
        if index >= .sources.count do
            fail Errors.BadParameterError{"PDF page index exceeds the document page count"}
        let source = .sources[index]
        var result = #move try decodePage(&.parser, source.objectId, source.resourcesId, source.mediaBoxId, source.cropBoxId, source.rotate, .Complete)
        return #move result
    }

    // Returns the size of the page at zero-based `index`, in PDF points, without decoding it.
    //
    // The size is the displayed region — the MediaBox intersected with the CropBox — turned by
    // the page's rotation. It costs the page's own attributes and nothing else, so a viewer can
    // lay a whole document out before a single page is decoded. An out-of-range index reports
    // [[Core.Errors.BadParameterError]].
    mtd pageSize(index: u64)->Math.Point fail
    {
        if index >= .sources.count do
            fail Errors.BadParameterError{"PDF page index exceeds the document page count"}
        let source = .sources[index]
        return try pageBoxSize(&.parser, source.objectId, source.mediaBoxId, source.cropBoxId, source.rotate)
    }

    // Returns the text of the page at zero-based `index`, in reading order.
    //
    // Invisible text layers are included, so stored OCR text remains searchable without painting
    // over the scan. Lines run from top to bottom and words from left to right, one space per word gap and one
    // line feed per line break, whatever order the file painted them in: the shape a search or a
    // copy expects. Only the text is decoded, with no image, path, or mask, so a page costs a
    // fraction of [[Gui.Pdf.Reader.loadPage]]; and the result is byte for byte the text that
    // page indexes once displayed, so an offset found here locates the same characters there.
    // An out-of-range index reports [[Core.Errors.BadParameterError]].
    mtd loadPageText(index: u64)->String fail
    {
        if index >= .sources.count do
            fail Errors.BadParameterError{"PDF page index exceeds the document page count"}
        let source = .sources[index]
        var page   = #move try decodePage(&.parser, source.objectId, source.resourcesId, source.mediaBoxId, source.cropBoxId, source.rotate, .TextOnly)
        var text   = TextIndex.build(&page)
        return #move text.text
    }
}
