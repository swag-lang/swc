#global internal
#global namespace Viewers.OpenDocument

using Core, Core.Errors, Gui

const ImageLimit      = 16 * 1024 * 1024'u64
const ImageCountLimit = 256'u64

private
{
    const ContentLimit  = 32 * 1024 * 1024'u64
    const MetadataLimit = 256 * 1024'u64
}

// Distinguishes the document surfaces that share the OpenDocument container.
enum Kind
{
    Text
    Spreadsheet
    Presentation
    Drawing
}

// One spreadsheet sheet, retaining its source name beside its reusable table model.
struct Sheet
{
    name:  String
    table: Table.Document
}

// One presentation slide, retaining its source name beside the isolated reader markup.
struct Slide
{
    name: String
    html: String
}

// One decoded document, ready for the reader surface appropriate to its kind.
struct Content
{
    kind:     Kind
    metadata: Metadata
    html:     String
    sheets:   Array'Sheet
    slides:   Array'Slide
}

func kindFromMime(mimeType: string)->Kind fail
{
    switch mimeType
    {
    case "application/vnd.oasis.opendocument.text", "application/vnd.oasis.opendocument.text-template":                 return .Text
    case "application/vnd.oasis.opendocument.spreadsheet", "application/vnd.oasis.opendocument.spreadsheet-template":   return .Spreadsheet
    case "application/vnd.oasis.opendocument.presentation", "application/vnd.oasis.opendocument.presentation-template": return .Presentation
    case "application/vnd.oasis.opendocument.graphics", "application/vnd.oasis.opendocument.graphics-template":         return .Drawing
    default: fail InvalidFormatError{Errors.mkString(texts().err_MimeType)}
    }
}

func flatKind(fileName: string)->Kind fail
{
    switch Path.lowercaseExtension(fileName).toString()
    {
    case ".fodt": return .Text
    case ".fods": return .Spreadsheet
    case ".fodp": return .Presentation
    case ".fodg": return .Drawing
    default:      fail InvalidFormatError{Errors.mkString(texts().err_MimeType)}
    }
}

func loadFlatContent(fileName: string)->Content fail
{
    let info = try File.info(fileName)
    if info.size > ContentLimit do
        fail UnsupportedFormatError{Errors.mkString(texts().err_TooLarge)}

    let bytes = try File.readAllBytes(fileName)
    if bytes.count > ContentLimit do
        fail UnsupportedFormatError{Errors.mkString(texts().err_TooLarge)}
    if not Utf8.isValid(bytes.toSlice()) do
        fail InvalidFormatError{Errors.mkString(texts().err_Encoding)}
    return try parseContent(cast(string, bytes.toSlice()), try flatKind(fileName))
}

func imageMediaType(path: string)->string
{
    switch Path.lowercaseExtension(path).toString()
    {
    case ".bmp":          return "bmp"
    case ".gif":          return "gif"
    case ".ico":          return "x-icon"
    case ".jpg", ".jpeg": return "jpeg"
    case ".png":          return "png"
    case ".tif", ".tiff": return "tiff"
    case ".webp":         return "webp"
    default:              return ""
    }
}

// Converts only bounded picture-package entries into data URIs; external references stay inert.
func loadImages(fileName: string, archive: const *Archive.Zip)->Array'EmbeddedImage
{
    var result: retval
    var total = 0'u64
    for &entry in archive.entries
    {
        if result.count == ImageCountLimit do
            break
        if not entry.path.startsWith("Pictures/", .Latin1NoCase) do
            continue
        let mediaType = imageMediaType(entry.path)
        if mediaType == "" or
           entry.uncompressedSize > ImageLimit or
           entry.uncompressedSize > ImageLimit - total do
            continue

        let bytes = catch Archive.Zip.loadEntry(fileName, entry) as imageError
        if imageError != null do
            continue

        var image: EmbeddedImage
        image.path      = entry.path
        image.uri       = Format.toString("data:image/%;base64,%", mediaType, Base64.encode(bytes.toSlice()))
        image.byteCount = bytes.count
        result.add(#move image)
        total += bytes.count
    }

    return result
}

// Loads an OpenDocument file, flat XML or zipped package, into the content the viewer presents.
// Fails when the package lacks `mimetype` or `content.xml`, or the content is too large or not
// UTF-8; styles and metadata are optional.
func loadContent(fileName: string)->Content fail
{
    switch Path.lowercaseExtension(fileName).toString()
    {
    case ".fodt", ".fods", ".fodp", ".fodg": return try loadFlatContent(fileName)
    }

    let archive = try Archive.Zip.load(fileName)
    var mime:    *Archive.ZipEntry?
    var content: *Archive.ZipEntry?
    var styles:  *Archive.ZipEntry?
    var meta:    *Archive.ZipEntry?
    for &entry in archive.entries
    {
        if entry.path == "mimetype" do
            mime = entry
        elif entry.path == "content.xml" do
            content = entry
        elif entry.path == "styles.xml" do
            styles = entry
        elif entry.path == "meta.xml" do
            meta = entry
    }

    if mime == null do
        fail InvalidFormatError{Errors.mkString(texts().err_MimeType)}
    if content == null do
        fail InvalidFormatError{Errors.mkString(texts().err_Content)}
    if content.uncompressedSize > ContentLimit do
        fail UnsupportedFormatError{Errors.mkString(texts().err_TooLarge)}

    let mimeBytes = try Archive.Zip.loadEntry(fileName, mime)
    let kind      = try kindFromMime(cast(string, mimeBytes.toSlice()))
    let bytes     = try Archive.Zip.loadEntry(fileName, content)
    if not Utf8.isValid(bytes.toSlice()) do
        fail InvalidFormatError{Errors.mkString(texts().err_Encoding)}
    var images: Array'EmbeddedImage
    if kind != .Spreadsheet do
        images = loadImages(fileName, &archive)
    var styleSource: String
    if styles != null and styles.uncompressedSize <= ContentLimit
    {
        let styleBytes = catch Archive.Zip.loadEntry(fileName, styles) as stylesError
        if stylesError == null and Utf8.isValid(styleBytes.toSlice()) do
            styleSource = cast(string, styleBytes.toSlice())
    }

    var metadata: Metadata
    if meta != null and meta.uncompressedSize <= MetadataLimit
    {
        let metadataBytes = catch Archive.Zip.loadEntry(fileName, meta) as metadataError
        if metadataError == null and Utf8.isValid(metadataBytes.toSlice()) do
            metadata = catch parseMetadata(cast(string, metadataBytes.toSlice()))
    }

    return try parseContentWithImages(cast(string, bytes.toSlice()), styleSource, kind, #move images, #move metadata)
}
