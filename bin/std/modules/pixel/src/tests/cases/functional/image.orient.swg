#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// A 2 x 3 picture whose pixels carry their reading order, 1 to 6, in the red channel:
//
//     1 2
//     3 4
//     5 6
func orientSample()->Image
{
    // The buffer is stored bottom row first.
    let bytes = [5'u8, 0'u8, 0'u8, 255'u8, 6'u8, 0'u8, 0'u8, 255'u8,
                 3'u8, 0'u8, 0'u8, 255'u8, 4'u8, 0'u8, 0'u8, 255'u8,
                 1'u8, 0'u8, 0'u8, 255'u8, 2'u8, 0'u8, 0'u8, 255'u8]
    return Image.create(2, 3, .RGBA8, bytes)
}

// Returns the rows of `image`, top first, as their red values.
func orientRows(image: const *Image)->String
{
    var result: #returntype
    for y in image.height
    {
        if y do
            result += "/"
        for x in image.width do
            result += Format.toString("%", image.pixelColor(x, y).r)
    }

    return result
}

// Every EXIF orientation stands the picture upright; 5 to 8 swap its sides.
#test
{
    let expected = ["12/34/56", "21/43/65", "65/43/21", "56/34/12", "135/246", "531/642", "642/531", "246/135"]
    for orientation in 1 to 8
    {
        var image = orientSample()
        image.orient(orientation)
        Swag.require(orientRows(&image) == expected[orientation - 1])
    }

    var unknown = orientSample()
    unknown.orient(9)
    Swag.require(orientRows(&unknown) == "12/34/56")
}

// The value-returning orientation helper transforms a copy and leaves its source unchanged.
#test
{
    let source = orientSample()
    let result = source.oriented(6)
    Swag.require(orientRows(&source) == "12/34/56")
    Swag.require(orientRows(&result) == "531/642")
}

// The orientation is read from the EXIF record a decoder keeps, whatever prefix precedes its
// TIFF header, and anything unreadable means upright.
#test
{
    // A little-endian TIFF header with one directory holding Orientation = 6.
    let tiff = [0x49'u8, 0x49'u8, 0x2A'u8, 0x00'u8, 0x08'u8, 0x00'u8, 0x00'u8, 0x00'u8,
                0x01'u8, 0x00'u8,
                0x12'u8, 0x01'u8, 0x03'u8, 0x00'u8, 0x01'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x06'u8, 0x00'u8, 0x00'u8, 0x00'u8,
                0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8]

    var record: ImageMetadata
    record.signature = 1
    record.tag       = "Exif"
    record.value.add(0'u8)
    for byte in tiff do
        record.value.add(byte)
    var records: Array'ImageMetadata
    records.add(#move record)
    Swag.require(Exif.orientationOf(records.toSlice()) == 6)

    var taggedImage = Image.create(2, 3, .RGBA8)
    taggedImage.metadata = records
    let upright = taggedImage.oriented(6)
    Swag.require(Exif.orientationOf(taggedImage.metadata.toSlice()) == 6)
    Swag.require(Exif.orientationOf(upright.metadata.toSlice()) == 1)
    Swag.require(upright.metadata.count == taggedImage.metadata.count)
    taggedImage.orient(6)
    Swag.require(Exif.orientationOf(taggedImage.metadata.toSlice()) == 1)

    records[0].value.clear()
    records[0].value.add(0x49'u8)
    Swag.require(Exif.orientationOf(records.toSlice()) == 1)
    var none: Array'ImageMetadata
    Swag.require(Exif.orientationOf(none.toSlice()) == 1)
}

// A prefixed little-endian IFD resets a SHORT value stored outside the IFD entry.
#test
{
    var littleEndian: ImageMetadata
    littleEndian.signature = 1
    littleEndian.tag       = "Exif"
    littleEndian.value.add(0'u8)
    littleEndian.value.add([0x49'u8, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00,
                            0x01, 0x00,
                            0x12, 0x01, 0x03, 0x00, 0x03, 0x00, 0x00, 0x00,
                            0x1A, 0x00, 0x00, 0x00,
                            0x00, 0x00, 0x00, 0x00,
                            0x06, 0x00, 0x02, 0x00, 0x03, 0x00])

    var prefixed = Image.create(1, 1, .RGBA8)
    prefixed.metadata.add(#move littleEndian)
    prefixed.orient(6)
    Swag.require(prefixed.metadata[0].value[27] == 1 and prefixed.metadata[0].value[28] == 0)
    Swag.require(prefixed.metadata[0].value[29] == 2 and prefixed.metadata[0].value[30] == 0)
    Swag.require(prefixed.metadata[0].value[31] == 3 and prefixed.metadata[0].value[32] == 0)
}

// Orientation normalization also handles a big-endian TIFF header without rewriting other fields.
#test
{
    let tiff = [0x4D'u8, 0x4D'u8, 0x00'u8, 0x2A'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x08'u8,
                0x00'u8, 0x01'u8,
                0x01'u8, 0x12'u8, 0x00'u8, 0x03'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x01'u8,
                0x00'u8, 0x06'u8, 0x00'u8, 0x00'u8,
                0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8]
    var record: ImageMetadata
    record.signature = 1
    record.tag       = "Exif"
    for byte in tiff do
        record.value.add(byte)

    var image = Image.create(2, 3, .RGBA8)
    image.metadata.add(#move record)
    Swag.require(Exif.orientationOf(image.metadata.toSlice()) == 6)
    image.orient(6)
    Swag.require(Exif.orientationOf(image.metadata.toSlice()) == 1)
    Swag.require(image.metadata[0].value.count == tiff.count)
    Swag.require(image.metadata[0].value[18] == 0 and image.metadata[0].value[19] == 1)
}
