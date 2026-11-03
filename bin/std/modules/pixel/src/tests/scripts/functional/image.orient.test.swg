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
        Swag.assert(orientRows(&image) == expected[orientation - 1])
    }

    var unknown = orientSample()
    unknown.orient(9)
    Swag.assert(orientRows(&unknown) == "12/34/56")
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
    Swag.assert(Exif.orientationOf(records.toSlice()) == 6)

    records[0].value.clear()
    records[0].value.add(0x49'u8)
    Swag.assert(Exif.orientationOf(records.toSlice()) == 1)
    var none: Array'ImageMetadata
    Swag.assert(Exif.orientationOf(none.toSlice()) == 1)
}
