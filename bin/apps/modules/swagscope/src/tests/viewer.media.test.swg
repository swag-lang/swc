#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// JPEG EXIF is interpreted from the preserved APP1 payload, while decodeMetadata remains optional.
#test
{
    let fileName = Testing.tempFilePath("scope-exif-", ".jpg")
    defer discard catch File.delete(fileName)
    var source = Image.create(8, 8, .RGB8)
    source.fill(Color.fromRgb(255, 255, 255))
    var record: ImageMetadata
    record.signature = 1
    record.tag       = "Exif"
    record.value     = "\0II\x2a\0\x08\0\0\0\x01\0\x0f\x01\x02\0\x06\0\0\0\x1a\0\0\0\0\0\0\0Camera"
    source.metadata.add(record)
    expect source.save(fileName)
    let decoded = expect Image.load(fileName)
    var data: MediaInfoData
    data.addImageMetadata(decoded.metadata.toSlice())
    var found = false
    for row in data.rows where row.name == "Make" and row.value == "Camera" do
        found = true
    Swag.assert(found)

    var file       = expect File.MappedFile.open(fileName)
    let region     = expect file.mapAll()
    let pixelsOnly = expect Image.decode(fileName, region.bytes(), {decodeMetadata: false})
    Swag.assert(pixelsOnly.isValid() and pixelsOnly.metadata.isEmpty())
    source.metadata[0].value = "\0II"
    var malformed: MediaInfoData
    malformed.addImageMetadata(source.metadata.toSlice())
    Swag.assert(malformed.rows.count == 2 and malformed.rows[1].field == .Unavailable)
}
