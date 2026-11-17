#global internal
#global namespace Viewers.Package

using Core

// What an office document says of itself in its package: the Office Open XML core and
// application parts, or the OpenDocument `meta.xml`. Every field is as written, empty when the
// package does not say.
struct DocumentProperties
{
    title:       String
    author:      String     // The creator the document names first.
    created:     String     // The day the document was created, `YYYY-MM-DD`.
    application: String     // The program that last saved it, without its build details.
}

// The largest property part read; properties are a few kilobytes.
const DocumentPropertiesLimit = 256'u64 * 1024

impl DocumentProperties
{
    // Reads the properties of the package `fileName`; a missing, oversized or damaged part leaves
    // its fields empty rather than failing.
    func read(fileName: string)->DocumentProperties
    {
        let archive = catch Archive.Zip.load(fileName) { return {}; }
        return read(fileName, &archive)
    }

    // Reads the properties of the package `fileName` from its already opened `archive`, as a reader
    // does on its loading worker; a missing, oversized or damaged part leaves its fields empty
    // rather than failing.
    func read(fileName: string, archive: const *Archive.Zip)->DocumentProperties
    {
        var result: #returntype

        // Office Open XML keeps its core properties and the saving program apart.
        if let core = archive.tryFindEntry("docProps/core.xml")
        {
            let text = readPart(fileName, core)
            result.title   = elementText(text, "title")
            result.author  = elementText(text, "creator")
            result.created = dayOf(elementText(text, "created"))
            if let application = archive.tryFindEntry("docProps/app.xml") do
                result.application = elementText(readPart(fileName, application), "Application")
            return result
        }

        // OpenDocument names the first author apart from the last one, and its generator with
        // its build after a dollar sign.
        if let meta = archive.tryFindEntry("meta.xml")
        {
            let text = readPart(fileName, meta)
            result.title  = elementText(text, "title")
            result.author = elementText(text, "initial-creator")
            if result.author.isEmpty() do
                result.author = elementText(text, "creator")
            result.created = dayOf(elementText(text, "creation-date"))
            let generator = elementText(text, "generator")
            let build     = Utf8.indexOf(generator, "$")
            result.application = build == Swag.U64.Max ? generator : String.from(Latin1.trim(generator.toString()[0 until build]))
        }

        return result
    }

    // Reports whether the package says nothing the information sheet writes.
    mtd const isEmpty()->bool => .title.isEmpty() and .author.isEmpty() and .created.isEmpty() and .application.isEmpty()

    // Appends what the document says of itself to the information sheet, under a heading of its own.
    mtd const describe(data: *MediaInfoData)
    {
        if .isEmpty() do
            return
        data.add(.Document, group: true)
        if not .title.isEmpty() do
            data.add(.Title, .title)
        if not .author.isEmpty() do
            data.add(.Author, .author)
        if not .created.isEmpty() do
            data.add(.Created, .created)
        if not .application.isEmpty() do
            data.add(.Application, .application)
    }
}

// Returns the text of one bounded package part, or nothing.
private func readPart(fileName: string, entry: const *Archive.ZipEntry)->String
{
    var result: #returntype
    if entry.uncompressedSize > DocumentPropertiesLimit do
        return result
    let bytes = catch Archive.Zip.loadEntry(fileName, entry) { return result; }
    result = String.from(cast(string, bytes.toSlice()))
    return result
}

// Returns the trimmed text of the first element whose local name is `name`.
private func elementText(source: String, name: string)->String
{
    var result: #returntype
    var scanner = Scanner.create(source.toString())
    var token:  Token
    var inside  = false
    while scanner.next(&token)
    {
        switch token.kind
        {
        case .Start:
            if not token.empty and token.isElement(name) do
                inside = true

        case .Text:
            if inside do
                result += token.text

        case .End:
            if inside and token.isElement(name) do
                return String.from(Latin1.trim(result.toString()))
        }
    }

    return {}
}

// Keeps the day of an ISO 8601 date and time, which is what a reader asks of a creation date.
private func dayOf(value: String)->String
{
    let text = value.toString()
    if text.count >= 10 and text[4] == '-'u8 and text[7] == '-'u8 do
        return String.from(text[0 until 10])
    return value
}
