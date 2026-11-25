#global internal
#global namespace Viewers.Odf

using Core

// Shared bounded ODF package identity and encryption check before any content is read.
func openPackage(fileName, mediaType, invalid, tooLarge, encrypted: string)->Archive.Zip fail
{
    if (try File.info(fileName)).size > 64 * 1024 * 1024 do
        fail Errors.UnsupportedFormatError{tooLarge}
    let archive = try Archive.Zip.load(fileName)
    if archive.entries.count > 4096 do
        fail Errors.UnsupportedFormatError{tooLarge}
    let mime = archive.tryFindEntry("mimetype")
    if mime
    {
        if mime.uncompressedSize > 256 do
            fail Errors.InvalidFormatError{invalid}
        let mimeBytes = try Archive.Zip.loadEntry(fileName, mime)
        if cast(string, mimeBytes.toSlice()) != mediaType do
            fail Errors.InvalidFormatError{invalid}
    }

    let parts    = Package.PartReader{fileName, &archive, invalid, tooLarge}
    let manifest = try parts.text("META-INF/manifest.xml", required: mime == null, limit: 1024 * 1024, allowDocumentType: true)
    var scan     = Package.Scanner.create(manifest)
    scan.allowDocumentType = true
    var rootType: String
    var rootEntry = false
    var depth = 0'u32
    var token: Package.Token
    while scan.next(&token)
    {
        if token.kind == .Start
        {
            if not depth and not token.isElement("manifest") do
                fail Errors.InvalidFormatError{invalid}
            if token.isElement("encryption-data") do
                fail Errors.UnsupportedFormatError{encrypted}
            if depth == 1 and token.isElement("file-entry") and (token.attribute("full-path") orelse "") == "/"
            {
                if rootEntry do
                    fail Errors.InvalidFormatError{invalid}
                rootEntry = true
                rootType = token.attribute("media-type") orelse ""
            }

            if not token.empty do
                depth += 1
        }
        elif token.kind == .End do
            depth -= 1
    }

    // Some producers leave the package type only in the manifest's root entry.
    if (rootEntry and rootType != mediaType) or (not mime and not rootEntry) do
        fail Errors.InvalidFormatError{invalid}

    return archive
}

// Safe embedded raster resolution shared by document readers; decoded URLs remain ZIP-local.
func imageHtml(fileName: string, archive: const *Archive.Zip, path: string, width, height: u32, description: string, encodedBytes: *u64)->String
{
    // ODF image URLs may be escaped, but every decoded component still stays inside the ZIP.
    let bytesPath = catch Net.Url.decodeComponent(path) { return {}; }
    let decoded   = cast(string, bytesPath.toSlice())
    if Utf8.contains(decoded, ":") do
        return {}
    let resolved = Package.resolvePath("", decoded)
    if resolved.isEmpty() do
        return {}
    let extension     = Path.lowercaseExtension(resolved)
    var media: string = ""
    switch extension.toString()
    {
    case ".jpg", ".jpeg": media = "image/jpeg"
    case ".png":          media = "image/png"
    case ".gif":          media = "image/gif"
    case ".webp":         media = "image/webp"
    default:              return {}
    }

    let entry = archive.tryFindEntry(resolved)
    if not entry or
       entry.uncompressedSize > 2 * 1024 * 1024 or
       encodedBytes[] + entry.uncompressedSize > 8 * 1024 * 1024 do
        return {}
    let bytes = catch Archive.Zip.loadEntry(fileName, entry) { return {}; }
    let html  = Package.embeddedImageHtml(bytes.toSlice(), media, width, height, description)
    if not html.isEmpty() do
        encodedBytes[] += bytes.count
    return html
}
