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
    if not mime or mime.uncompressedSize > 256 do
        fail Errors.InvalidFormatError{invalid}
    let mimeBytes = try Archive.Zip.loadEntry(fileName, mime)
    if cast(string, mimeBytes.toSlice()) != mediaType do
        fail Errors.InvalidFormatError{invalid}
    let parts    = Package.PartReader{fileName, &archive, invalid, tooLarge}
    let manifest = try parts.text("META-INF/manifest.xml", required: false, limit: 1024 * 1024)
    var scan     = Package.Scanner.create(manifest)
    var token: Package.Token
    while scan.next(&token)
    {
        if token.kind == .Start and token.isElement("encryption-data") do
            fail Errors.UnsupportedFormatError{encrypted}
    }

    return archive
}
