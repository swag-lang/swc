#global public
#global namespace Exif

using Core, Core.Errors

// Identifies the EXIF directory that owns a property.
enum Directory
{
    Image     // Main image attributes from the first TIFF directory.
    Photo     // Camera and exposure attributes from the EXIF directory.
    Gps       // Geographic attributes from the GPS directory.
}

// Owns a readable EXIF value while retaining its original directory and numeric tag.
struct Property
{
    public
    {
        directory: Directory     // Namespace in which the tag is defined.
        tag:       u16           // Original TIFF or EXIF tag number.
        value:     String        // Owned text; rationals retain their numerator and denominator.
    }
}

impl Property
{
    // Returns the standard EXIF field name, or the numeric tag for an unknown field.
    mtd const name()->String
    {
        if .directory == .Gps
        {
            switch .tag
            {
            case 0:  return String.from("GPSVersionID")
            case 1:  return String.from("GPSLatitudeRef")
            case 2:  return String.from("GPSLatitude")
            case 3:  return String.from("GPSLongitudeRef")
            case 4:  return String.from("GPSLongitude")
            case 5:  return String.from("GPSAltitudeRef")
            case 6:  return String.from("GPSAltitude")
            case 7:  return String.from("GPSTimeStamp")
            case 18: return String.from("GPSMapDatum")
            case 29: return String.from("GPSDateStamp")
            }
        }
        else
        {
            switch .tag
            {
            case 0x0100: return String.from("ImageWidth")
            case 0x0101: return String.from("ImageLength")
            case 0x010E: return String.from("ImageDescription")
            case 0x010F: return String.from("Make")
            case 0x0110: return String.from("Model")
            case 0x0112: return String.from("Orientation")
            case 0x011A: return String.from("XResolution")
            case 0x011B: return String.from("YResolution")
            case 0x0128: return String.from("ResolutionUnit")
            case 0x0131: return String.from("Software")
            case 0x0132: return String.from("DateTime")
            case 0x013B: return String.from("Artist")
            case 0x8298: return String.from("Copyright")
            case 0x829A: return String.from("ExposureTime")
            case 0x829D: return String.from("FNumber")
            case 0x8822: return String.from("ExposureProgram")
            case 0x8827: return String.from("PhotographicSensitivity")
            case 0x9000: return String.from("ExifVersion")
            case 0x9003: return String.from("DateTimeOriginal")
            case 0x9004: return String.from("DateTimeDigitized")
            case 0x9011: return String.from("OffsetTimeOriginal")
            case 0x9201: return String.from("ShutterSpeedValue")
            case 0x9202: return String.from("ApertureValue")
            case 0x9204: return String.from("ExposureBiasValue")
            case 0x9207: return String.from("MeteringMode")
            case 0x9209: return String.from("Flash")
            case 0x920A: return String.from("FocalLength")
            case 0x927C: return String.from("MakerNote")
            case 0x9286: return String.from("UserComment")
            case 0xA001: return String.from("ColorSpace")
            case 0xA002: return String.from("PixelXDimension")
            case 0xA003: return String.from("PixelYDimension")
            case 0xA403: return String.from("WhiteBalance")
            case 0xA405: return String.from("FocalLengthIn35mmFilm")
            case 0xA420: return String.from("ImageUniqueID")
            case 0xA431: return String.from("BodySerialNumber")
            case 0xA433: return String.from("LensMake")
            case 0xA434: return String.from("LensModel")
            case 0xA435: return String.from("LensSerialNumber")
            }
        }

        return Format.toString("Tag %", .tag)
    }
}

// Reads the main, photo, and GPS properties from an EXIF TIFF header in either byte order.
//
// `bytes` starts at `II` or `MM`, without a JPEG `Exif\0\0` prefix. The result owns its text;
// input bytes are borrowed only during this call. This is an optional interpretation step after
// decoding an image with [[Pixel.DecodeOptions.decodeMetadata]] enabled. Pixel keeps opaque
// [[Pixel.ImageMetadata]] records unchanged for round trips.
//
// Fails for malformed headers, offsets, field storage, cyclic directory pointers, or more than
// 1024 entries. Thumbnail directories and unsupported TIFF field types are skipped. Text and
// numeric arrays are limited to 4096 bytes and 64 values respectively, with an ellipsis when
// shortened. Undefined binary values are summarized by byte count. Rational zero denominators
// remain visible as fractions and are never divided.
func decode(bytes: const [..] u8)->Array'Property fail
{
    var reader = Reader{bytes: bytes}
    try reader.checkRange(0, 8)
    if bytes[0] == 'I' and bytes[1] == 'I' do
        reader.littleEndian = true
    elif bytes[0] != 'M' or bytes[1] != 'M' do
        fail InvalidFormatError{"EXIF header has no TIFF byte order"}
    if try reader.number(2, 2) != 42 do
        fail InvalidFormatError{"EXIF header has no TIFF signature"}

    var result: retval
    let offset = try reader.number(4, 4)
    if offset < 8 do
        fail InvalidFormatError{"EXIF directory overlaps its TIFF header"}
    try reader.readDirectory(offset, .Image, &result)
    return result
}

private struct Reader
{
    bytes:        const [..] u8
    littleEndian: bool
    visited:      Array'u64
    entries:      u64
}

private impl Reader
{
    mtd const checkRange(offset, size: u64) fail
    {
        if offset > .bytes.count or size > .bytes.count - offset do
            fail InvalidFormatError{"EXIF field exceeds its metadata record"}
    }

    mtd const number(offset, size: u64)->u64 fail
    {
        try .checkRange(offset, size)
        var result = 0'u64
        for index in size
        {
            let shift = .littleEndian ? index * 8 : (size - 1 - index) * 8
            result |= cast(u64) .bytes[offset + index] << shift
        }

        return result
    }

    mtd const textValue(offset, count: u64)->String
    {
        var result: retval
        let limit = Math.min(count, 4096)
        for index in limit
        {
            let byte = .bytes[offset + index]
            if !byte do
                return result
            result += cast(rune) (byte < 32 and byte != 9 and byte != 10 and byte != 13 ? 32 : byte)
        }

        if count > limit do
            result += "…"
        return result
    }

    mtd const fieldValue(offset, count, kind, size: u64)->String fail
    {
        if kind == 2 do
            return .textValue(offset, count)
        if kind == 7 do
            return Format.toString("% bytes", count)

        var result: retval
        for index in Math.min(count, 64)
        {
            if index do
                result += ", "
            let at = offset + index * size
            if kind == 5 or kind == 10
            {
                let numerator   = try .number(at, 4)
                let denominator = try .number(at + 4, 4)
                if kind == 10 do
                    result += Format.toString("%/%", cast #bit(s32) cast(u32) numerator, cast #bit(s32) cast(u32) denominator)
                else do
                    result += Format.toString("%/%", numerator, denominator)
            }
            else
            {
                let value = try .number(at, size)
                result += kind == 9 ? Format.toString("%", cast #bit(s32) cast(u32) value) : Format.toString("%", value)
            }
        }

        if count > 64 do
            result += ", …"
        return result
    }

    mtd readDirectory(offset: u64, directory: Directory, result: *Array'Property) fail
    {
        for previous in .visited where previous == offset do
            fail InvalidFormatError{"EXIF directory pointer forms a cycle"}
        .visited.add(offset)
        let count = try .number(offset, 2)
        .entries += count
        if .entries > 1024 do
            fail UnsupportedFormatError{"EXIF metadata exceeds 1024 directory entries"}
        try .checkRange(offset + 2, count * 12 + 4)

        for index in count
        {
            let at       = offset + 2 + index * 12
            let tag      = cast(u16) try .number(at, 2)
            let kind     = try .number(at + 2, 2)
            let elements = try .number(at + 4, 4)
            var size     = 0'u64
            switch kind
            {
            case 1, 2, 7: size = 1
            case 3:       size = 2
            case 4, 9:    size = 4
            case 5, 10:   size = 8
            }

            if !size or !elements do
                continue
            let byteCount = elements * size
            let valueAt   = byteCount <= 4 ? at + 8 : try .number(at + 8, 4)
            try .checkRange(valueAt, byteCount)
            if directory == .Image and (tag == 0x8769 or tag == 0x8825)
            {
                if kind != 4 or elements != 1 do
                    fail InvalidFormatError{"EXIF directory pointer needs one LONG value"}
                let next = try .number(valueAt, 4)
                if next < 8 do
                    fail InvalidFormatError{"EXIF directory overlaps its TIFF header"}
                try .readDirectory(next, tag == 0x8769 ? .Photo : .Gps, result)
                continue
            }

            var property = Property{directory: directory, tag: tag}
            property.value = try .fieldValue(valueAt, elements, kind, size)
            result.add(#move property)
        }
    }
}
