#global public

using Core

// Names one image file format and the filename extensions that select it.
//
// An encoder or a decoder declares this once, and the registry derives extension
// matching from it: [[Pixel.Image.canSave]], [[Pixel.Image.canLoad]] and the codec
// lookup all read the same declaration, so a codec cannot claim an extension its
// format does not list.
//
// A user interface enumerates the supported formats with
// [[Pixel.Image.encodableFormats]] or [[Pixel.Image.decodableFormats]] and builds
// its file filters from them.
struct ImageFormat
{
    public
    {
        // Display name of the format, such as `PNG - Portable Network Graphics`.
        //
        // It is a literal with static storage, so a user interface can hold it without
        // copying it. It is deliberately not translated: these are format names.
        name: string

        // Accepted extensions, lowercase, dot-prefixed, separated by `;`.
        //
        // The first one is canonical: it is the extension a file dialog appends when the
        // user types a bare name. `.jpg;.jpeg` is a format with two spellings, not two
        // formats. The separator matches the filter convention of the `gui` file dialog,
        // so the field can be handed to it unchanged.
        extensions: string
    }
}

impl ImageFormat
{
    // Reports whether this format claims `fileName`, by its extension alone.
    //
    // The comparison is case-insensitive; no file is opened and no content is read.
    // An empty name, or a name without an extension, matches nothing rather than being
    // an error: a file dialog asks this question while its name editor is still empty.
    mtd const matches(fileName: string)->bool
    {
        if @countof(fileName) == 0 do
            return false

        let ext = Path.lowercaseExtension(fileName)
        if ext.isEmpty() do
            return false
        for candidate in Tokenize.split(.extensions, ';'rune) where ext == candidate do
            return true
        return false
    }
}
