#global public

using Core

// One heading in document order, independent of the current layout and zoom.
struct DocumentHeading
{
    public
    {
        title:        String     // Owned plain text of the heading.
        level:        u32        // Heading level, from one through six.
        sourceOffset: u64        // Byte offset in the document source, accepted by the view's revealFileOffset method.
    }
}
