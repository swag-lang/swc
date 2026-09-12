#global public
#global namespace Markdown

using Core

// Returns owned headings in source order, using the same block and inline syntax as the view.
//
// Fenced code, metadata, and other non-heading blocks contribute no entries. Offsets address
// the supplied UTF-8 source and can be passed to [[Gui.Markdown.View.revealHeading]].
func parseHeadings(source: string)->Array'DocumentHeading
{
    var result: retval
    let blocks = parseBlocks(source, headingsOnly: true)
    var inline: InlineView
    for &block in blocks where block.kind >= .Heading1 and block.kind <= .Heading6
    {
        var heading: DocumentHeading
        inline.parse(block.text.toString())
        heading.title        = inline.text()
        heading.level        = cast(u32) block.kind - cast(u32) BlockKind.Heading1 + 1
        heading.sourceOffset = block.sourceOffset
        result.add(#move heading)
    }

    return result
}
