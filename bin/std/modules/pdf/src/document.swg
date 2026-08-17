#global public

using Core

// Stores the standard descriptive fields of a PDF document.
struct Metadata
{
    public
    {
        title:    String     // Document title.
        author:   String     // Person or organization that created the content.
        subject:  String     // Short description of the document.
        keywords: String     // Search terms associated with the document.
        creator:  String     // Application that created the source content.
        producer: String     // Application that wrote the PDF representation.
    }
}

// Owns an editable PDF document.
struct Document
{
    public
    {
        metadata: Metadata             // Descriptive document fields.
        readonly pages: Array'Page     // Pages in display order.
    }
}

public impl Document
{
    // Creates an empty PDF document.
    func create()->Document
    {
        var result: retval
        return result
    }

    // Decodes one complete PDF byte buffer.
    //
    // The document copies all content it retains. The input may be released after
    // this function returns. Encryption and embedded executable content are not
    // supported; embedded actions are ignored rather than executed.
    func decode(bytes: const [..] u8)->Document fail
    {
        return try decodeDocument(bytes)
    }

    // Loads and decodes every page of a PDF file.
    //
    // Use [[Pdf.Reader.open]] when pages should be decoded on demand.
    func load(fileName: string)->Document fail
    {
        var reader = try Reader.open(fileName)
        var result = Document.create()
        result.metadata = reader.metadata
        for index in reader.pageCount()
        {
            var page = try reader.loadPage(index)
            result.addPage(#move page)
        }
        return result
    }

    // Appends a page and transfers its owned content into the document.
    mtd addPage(page: #move Page)
    {
        Debug.assert(page.width > 0 and page.height > 0 and Math.isFinite(page.width) and Math.isFinite(page.height), "invalid page dimensions")
        .pages.add(#move page)
    }

    // Removes the page at `index` and preserves the order of the remaining pages.
    mtd removePage(index: u64)
    {
        Debug.assert(index < .pages.count, "page index out of range")
        .pages.removeAt(index)
    }

    // Returns a mutable borrowed page for editing.
    //
    // The pointer remains valid until a page is added to or removed from the document.
    mtd editPage(index: u64)->*Page
    {
        Debug.assert(index < .pages.count, "page index out of range")
        return &.pages[index]
    }

    // Encodes the complete document as PDF 1.7 bytes.
    //
    // The writer emits a deterministic classic cross-reference table and Flate
    // compressed content and image streams. It fails when text cannot be represented
    // by the writer's Windows-1252 Helvetica encoding.
    mtd const encode()->Array'u8 fail
    {
        return try encodeDocument(me)
    }

    // Encodes and writes the complete document to `fileName`.
    mtd const save(fileName: string) fail
    {
        let bytes = try .encode()
        discard try File.writeAllBytes(fileName, bytes.toSlice())
    }
}
