#global public

using Core

// Names one video file format and the filename extensions that select it.
//
// A decoder or an encoder declares this once, and the registry derives extension matching
// from it: [[Video.Reader.canOpen]], [[Video.Writer.canCreate]] and the codec lookup all
// read the same declaration, so a codec cannot claim an extension its format does not list.
//
// A user interface enumerates the supported formats with [[Video.Reader.decodableFormats]]
// or [[Video.Writer.encodableFormats]] and builds its file filters from them.
struct StreamFormat
{
    public
    {
        // Display name of the format, such as `Y4M - YUV4MPEG2 video`.
        //
        // It is a literal with static storage, so a user interface can hold it without
        // copying it. It is deliberately not translated: these are format names.
        name: string = ""

        // Accepted extensions, lowercase, dot-prefixed, separated by `;`.
        //
        // The first one is canonical: it is the extension a file dialog appends when the user
        // types a bare name. The separator matches the filter convention of the `gui` file
        // dialog, so the field can be handed to it unchanged.
        extensions: string = ""
    }
}

impl StreamFormat
{
    // Reports whether this format claims `fileName`, by its extension alone.
    //
    // The comparison is case-insensitive; no file is opened and no content is read. An empty
    // name, or a name without an extension, matches nothing rather than being an error: a file
    // dialog asks this question while its name editor is still empty.
    mtd const matches(fileName: string)->bool
    {
        if !@countof(fileName) do
            return false

        let extension = Path.lowercaseExtension(fileName)
        if extension.isEmpty() do
            return false
        for candidate in Tokenize.split(.extensions, ';'rune) where extension == candidate do
            return true
        return false
    }
}
