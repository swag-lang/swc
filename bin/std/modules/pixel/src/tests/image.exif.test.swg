#global if #command == Swag.CompilerCommand.Test
#global private

using Core

func exifNumber(bytes: *Array'u8, at, value, size: u64, little: bool)
{
    for index in size
    {
        let shift = little ? index * 8 : (size - 1 - index) * 8
        bytes[at + index] = cast(u8) ((value >> shift) & 255)
    }
}

func exifEntry(bytes: *Array'u8, at: u64, tag, kind, count, value: u64, little: bool)
{
    exifNumber(bytes, at, tag, 2, little)
    exifNumber(bytes, at + 2, kind, 2, little)
    exifNumber(bytes, at + 4, count, 4, little)
    exifNumber(bytes, at + 8, value, kind == 3 and count == 1 ? 2 : 4, little)
}

func exifFixture(little: bool)->Array'u8
{
    var result: retval
    result.resize(124)
    result[0] = little ? 'I'u8 : 'M'u8
    result[1] = result[0]
    exifNumber(&result, 2, 42, 2, little)
    exifNumber(&result, 4, 8, 4, little)
    exifNumber(&result, 8, 3, 2, little)
    exifEntry(&result, 10, 0x010F, 2, 6, 50, little)
    exifEntry(&result, 22, 0x0112, 3, 1, 6, little)
    exifEntry(&result, 34, 0x8769, 4, 1, 64, little)
    for byte, index in "Camera" do
        result[50 + index] = byte
    exifNumber(&result, 64, 3, 2, little)
    exifEntry(&result, 66, 0x829A, 5, 1, 108, little)
    exifEntry(&result, 78, 0x9204, 10, 1, 116, little)
    exifEntry(&result, 90, 0x8827, 3, 1, 400, little)
    exifNumber(&result, 108, 1, 4, little)
    exifNumber(&result, 112, 125, 4, little)
    exifNumber(&result, 116, 0xFFFFFFFF, 4, little)
    exifNumber(&result, 120, 3, 4, little)
    return result
}

// Inline and offset fields, nested directories, and signed fractions agree in both byte orders.
#test
{
    for little in [true, false]
    {
        var bytes      = exifFixture(little)
        let properties = expect Exif.decode(bytes.toSlice())
        bytes.clear()
        Swag.assert(properties.count == 5)
        Swag.assert(properties[0].name() == "Make" and properties[0].value == "Camera")
        Swag.assert(properties[1].name() == "Orientation" and properties[1].value == "6")
        Swag.assert(properties[2].directory == .Photo and properties[2].value == "1/125")
        Swag.assert(properties[3].value == "-1/3")
        Swag.assert(properties[4].name() == "PhotographicSensitivity" and properties[4].value == "400")
    }
}

// Every truncated prefix is rejected, including a payload ending inside a rational.
#test
{
    let bytes = exifFixture(true)
    for length in bytes.count
    {
        discard catch Exif.decode(bytes.toSlice()[until length]) as error
        Swag.assert(error != null)
    }
}

// Malformed pointers and huge counts cannot escape the record or recurse indefinitely.
#test
{
    var bytes = exifFixture(true)
    exifNumber(&bytes, 42, 8, 4, true)
    discard catch Exif.decode(bytes.toSlice()) as cycle
    Swag.assert(cycle != null)
    exifNumber(&bytes, 42, 64, 4, true)
    exifNumber(&bytes, 18, 0xFFFFFFFF, 4, true)
    discard catch Exif.decode(bytes.toSlice()) as offset
    Swag.assert(offset != null)
    exifNumber(&bytes, 18, 50, 4, true)
    exifNumber(&bytes, 14, 0xFFFFFFFF, 4, true)
    discard catch Exif.decode(bytes.toSlice()) as count
    Swag.assert(count != null)
}

// GPS tags keep their own namespace, and a zero denominator remains readable without division.
#test
{
    var bytes = exifFixture(false)
    exifNumber(&bytes, 34, 0x8825, 2, false)
    exifNumber(&bytes, 66, 2, 2, false)
    exifNumber(&bytes, 112, 0, 4, false)
    let properties = expect Exif.decode(bytes.toSlice())
    Swag.assert(properties[2].directory == .Gps)
    Swag.assert(properties[2].name() == "GPSLatitude" and properties[2].value == "1/0")
}
