#global internal
#global namespace Viewers.OpenDocument

using Core, Core.Errors, Gui

private const MetadataValueLimit = 512'u64

// Preserves the display-safe document properties without treating metadata as executable content.
struct Metadata
{
    title:   String
    subject: String
    creator: String
}

// The document property an element of the metadata stream fills, if any.
enum MetadataField
{
    None
    Title
    Subject
    Creator
}

// Collapses metadata whitespace after XML entity decoding, keeping a title suitable for window chrome.
func metadataValue(source: string)->String
{
    let decoded = decodeXmlText(source)
    var result:       retval
    var pendingSpace: bool
    for character in decoded
    {
        if character == ' ' or character == '\t' or character == '\r' or character == '\n'
        {
            if not result.isEmpty() do
                pendingSpace = true
            continue
        }

        if pendingSpace
        {
            result.append(cast(rune, ' '))
            pendingSpace = false
        }

        result.append(character)
        if result.count >= MetadataValueLimit do
            return result
    }

    return result
}

// Collects the small display-safe property set that applies to every OpenDocument family.
struct MetadataReader
{
    metadata: Metadata
    field:    MetadataField
    depth:    u64
    text:     String
}

private impl MetadataReader
{
    // Starts capturing the text of a title, subject or creator element, counting nested elements so
    // the capture ends with the element that began it.
    mtd startTag(tag: const *Tag)
    {
        if .field != .None
        {
            .depth += 1
            return
        }

        switch tag.name.toString()
        {
        case "dc:title":   .field = .Title
        case "dc:subject": .field = .Subject
        case "dc:creator": .field = .Creator
        default:           return
        }

        .depth = 1
        .text.clear()
    }

    mtd appendText(text: string)
    {
        if .field == .None or .text.count >= MetadataValueLimit do
            return
        let count = Math.min(text.count, MetadataValueLimit - .text.count)
        .text += text[0 until count]
    }

    // Ends the capture at the element that began it, keeping the first title, subject and creator
    // found.
    mtd endTag(_: const *Tag)
    {
        if .field == .None do
            return
        .depth -= 1
        if .depth do
            return

        let value = metadataValue(.text)
        switch .field
        {
        case .Title where .metadata.title.isEmpty():     .metadata.title = #move value
        case .Subject where .metadata.subject.isEmpty(): .metadata.subject = #move value
        case .Creator where .metadata.creator.isEmpty(): .metadata.creator = #move value
        default: discard value
        }

        .field = .None
    }
}

// Reads the document properties of a `meta.xml` payload or of a flat XML document.
//
// The same tag boundary checks apply as for document content.
func parseMetadata(source: string)->Metadata fail
{
    var reader: MetadataReader
    var textStart = 0'u64
    var at        = 0'u64
    while at < source.count
    {
        if source[at] != '<'
        {
            at += 1
            continue
        }

        if at > textStart do
            reader.appendText(source[textStart until at])
        let end = try tagEnd(source, at)
        let tag = parseTag(source[at + 1 until end])
        if not tag.name.isEmpty()
        {
            if tag.closing
            {
                reader.endTag(&tag)
            }
            else
            {
                reader.startTag(&tag)
                if tag.selfClosing do
                    reader.endTag(&tag)
            }
        }

        at        = end + 1
        textStart = at
    }

    if textStart < source.count do
        reader.appendText(source[textStart to])
    return #move reader.metadata
}
