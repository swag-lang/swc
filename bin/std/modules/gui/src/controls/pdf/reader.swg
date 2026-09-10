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
    // Lines run from top to bottom and words from left to right, one space per word gap and one
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
