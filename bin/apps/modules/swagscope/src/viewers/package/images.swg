#global internal
#global namespace Viewers.Package

using Core, Pixel

private struct ImageLink
{
    id:   String
    path: String
}

// Embedded images are resolved through document relationships, never through network URLs.
struct ImageCatalog
{
    links:        Array'ImageLink
    fileName:     string = ""
    archive:      const *Archive.Zip?
    encodedBytes: u64
}

impl ImageCatalog
{
    func load(fileName: string, archive: const *Archive.Zip, baseDirectory, relationsPath,
              invalidMessage, tooLargeMessage: string)->ImageCatalog fail
    {
        var result = ImageCatalog{fileName: fileName, archive: archive}
        let entry = archive.tryFindEntry(relationsPath)
        if not entry do
            return result
        if entry.uncompressedSize > 1024 * 1024 do
            fail Errors.UnsupportedFormatError{tooLargeMessage}
        let bytes = try Archive.Zip.loadEntry(fileName, entry)
        var scan = Package.Scanner.create(cast(string, bytes.toSlice()))
        var token: Package.Token
        while scan.next(&token)
        {
            if token.kind != .Start or not token.isElement("Relationship") do
                continue
            let kind = token.attribute("Type") orelse ""
            if not Utf8.contains(kind, "/image") or token.attribute("TargetMode") == "External" do
                continue
            let id = token.attribute("Id") orelse ""
            let target = token.attribute("Target") orelse ""
            let path = resolveRelationshipTarget(baseDirectory, target)
            if id.count and not path.isEmpty() do
                result.links.add(ImageLink{String.from(id), path})
            if result.links.count > 1024 do
                fail Errors.UnsupportedFormatError{tooLargeMessage}
        }
        if scan.damaged do
            fail Errors.InvalidFormatError{invalidMessage}
        return result
    }

    // Produces a self-contained image only after a bounded metadata decode succeeds.
    internal mtd html(id: string, width, height: u32)->String
    {
        if not id.count or .archive == null do
            return {}
        for &link in .links where link.id == id
        {
            let path = link.path.toString()
            let extension = Path.lowercaseExtension(path)
            var mediaType: string
            if extension == ".png" do
                mediaType = "image/png"
            elif extension == ".jpg" or extension == ".jpeg" do
                mediaType = "image/jpeg"
            elif extension == ".gif" do
                mediaType = "image/gif"
            elif extension == ".webp" do
                mediaType = "image/webp"
            else do
                return {}
            let entry = .archive.tryFindEntry(path)
            if not entry or entry.uncompressedSize > 2 * 1024 * 1024 or
               .encodedBytes + entry.uncompressedSize > 8 * 1024 * 1024 do
                return {}
            let bytes = catch Archive.Zip.loadEntry(.fileName, entry) { return {} }
            var options = DecodeOptions{decodePixels: false}
            options.maxInputBytes = 2 * 1024 * 1024
            options.maxPixels = 16 * 1024 * 1024
            options.maxDecodedBytes = 64 * 1024 * 1024
            discard catch Image.decode(path, bytes.toSlice(), options) { return {} }
            .encodedBytes += bytes.count
            var result: String = "<img style=\"max-width:100%;height:auto\" src=\"data:"
            if width and height
            {
                result = Format.toString("<img width=\"%\" height=\"%\" style=\"max-width:100%%;height:auto\" src=\"data:", width, height)
            }
            result += mediaType
            result += ";base64,"
            result += Base64.encode(bytes.toSlice())
            result += "\">"
            return result
        }
        return {}
    }
}
