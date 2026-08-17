#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Builds classic PDF files from their parts.
//
// The reader locates objects by scanning, so a fixture needs no cross-reference table; that
// keeps a test case readable as the object graph it is really about.

// Appends one plain object, numbered `number`.
func addObject(bytes: *Array'u8, number: u32, body: string)
{
    bytes.add(cast(const [..] u8) Format.toString("% 0 obj\n", number).toString())
    bytes.add(cast(const [..] u8) body)
    bytes.add(cast(const [..] u8) "\nendobj\n")
}

// Appends one stream object whose `/Length` is computed from the payload.
func addStreamObject(bytes: *Array'u8, number: u32, dictionary: string, stream: const [..] u8)
{
    bytes.add(cast(const [..] u8) Format.toString("% 0 obj\n<< % /Length % >>\nstream\n", number, dictionary, @countof(stream)).toString())
    bytes.add(stream)
    bytes.add(cast(const [..] u8) "\nendstream\nendobj\n")
}

// Builds a one-page document around `content`.
//
// Objects 1 to 4 are the catalog, the page tree, the page, and the content stream, so a test
// numbers its own objects from 5 up and names them from `resources`.
func singlePagePdf(resources: string, content: const [..] u8, extra: const [..] u8, mediaBox = "[0 0 200 100]")->Array'u8
{
    var result: retval
    result.add(cast(const [..] u8) "%PDF-1.7\n")
    addObject(&result, 1, "<< /Type /Catalog /Pages 2 0 R >>")
    addObject(&result, 2, "<< /Type /Pages /Count 1 /Kids [3 0 R] >>")
    addObject(&result, 3, Format.toString("<< /Type /Page /Parent 2 0 R /MediaBox % /Resources << % >> /Contents 4 0 R >>", mediaBox, resources).toString())
    addStreamObject(&result, 4, "", content)
    result.add(extra)
    result.add(cast(const [..] u8) "trailer\n<< /Root 1 0 R >>\n%%EOF\n")
    return result
}

// Returns the one item of `kind` a fixture page is expected to hold.
func onlyItem(page: const *Pdf.Page, kind: Pdf.ItemKind)->const *Pdf.Item
{
    var result: #null const *Pdf.Item
    var count = 0'u64
    for item in page.items where item.kind == kind
    {
        result = item
        count  += 1
    }

    @assert(count == 1)
    return result!
}

// Concatenates the UTF-8 of every text item, in paint order.
func pageText(page: const *Pdf.Page)->String
{
    var result: retval
    for item in page.items where item.kind == .Text do
        result += item.textValue()
    return result
}
