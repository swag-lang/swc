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

// Owns a mapped PDF source and decodes its pages on demand.
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
        region:           File.MappedRegion
        parser:           PdfParser
        sources:          Array'PageSource
    }
}

impl Reader
{
    // Opens a PDF file through a read-only mapping and indexes its pages.
    //
    // Page streams and resources are decoded only by [[Gui.Pdf.Reader.loadPage]]. Encryption and
    // embedded executable content are not supported; embedded actions are ignored rather than
    // executed.
    func open(fileName: string)->Reader fail
    {
        var file = #move try File.MappedFile.open(fileName)
        var result: retval
        result.region       = #move try file.mapAll()
        result.parser.bytes = result.region.bytes()
        try indexDocument(&result.parser, &result.documentMetadata, &result.sources)
        return result
    }

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
        var result = #move try decodePage(&.parser, source.objectId, source.resourcesId, source.mediaBoxId, source.cropBoxId, source.rotate)
        return #move result
    }
}
