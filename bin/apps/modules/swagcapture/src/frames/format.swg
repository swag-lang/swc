#global namespace Frames

// A frame file holds the pictures of a timed capture. It is written beside the capture while the
// recording runs and only appended to, so a save of the capture never rewrites it and a recording
// cut short still holds every frame written before the cut.
//
// Layout, little-endian:
//
//   header   magic u64, version u32, width u32, height u32, pixel format u32, reserved u64
//   record   tag u32, kind u32, time u64, x u32, y u32, w u32, h u32, payload size u32,
//            reserved u32, then the payload: the Deflate-compressed pixels of the rectangle
//            (x, y, w, h), top row first, in top-left picture coordinates
//   index    tag u32, reserved u32, count u64, then one entry per record:
//            offset u64, time u64, kind u32, reserved u32
//   footer   index offset u64, end time u64, end magic u64
//
// A key record carries the whole picture; a delta record carries only the rectangle that changed
// since the previous frame, and an empty rectangle repeats it. The index and the footer are
// written when the recording ends; a file without them is read by scanning its records.

const Magic          = 0x454D415246475753'u64     // "SWGFRAME"
const EndMagic       = 0x00444E4546475753'u64     // "SWGFEND\0"
const Version        = 1'u32
const RecordTag      = 0x4D415246'u32     // "FRAM"
const IndexTag       = 0x58444E49'u32     // "INDX"
const HeaderSize     = 32'u64
const RecordSize     = 40'u64
const IndexEntrySize = 24'u64
const FooterSize     = 24'u64

// Time between two key records, in microseconds. It bounds how many records a seek replays.
const KeyInterval = 1_000_000'u64

// What a record carries.
enum FrameKind: u32
{
    Key       // The whole picture.
    Delta     // The rectangle changed since the previous frame.
}

// Returns the record kind stored as `value`.
func frameKind(value: u32)->FrameKind fail
{
    switch value
    {
    case cast(u32, FrameKind.Key):   return .Key
    case cast(u32, FrameKind.Delta): return .Delta
    }

    fail Errors.InvalidFormatError{}
}

// Returns the pixel format stored as `value`. A frame file holds the 32-bit pictures a screen
// grab produces.
func framePixelFormat(value: u32)->PixelFormat fail
{
    switch value
    {
    case cast(u32, PixelFormat.BGRA8): return .BGRA8
    case cast(u32, PixelFormat.RGBA8): return .RGBA8
    }

    fail Errors.InvalidFormatError{}
}

// Where one frame is stored and when it is shown.
struct Entry
{
    offset: u64           // Position of the record in the file.
    time:   u64           // Time the frame is shown, in microseconds from the start.
    kind:   FrameKind     // Whether the record carries the whole picture.
}

// A rectangle of a frame, in top-left picture coordinates.
struct Area
{
    x, y, w, h: s32
}

impl Area
{
    mtd const isEmpty()->bool => .w <= 0 or .h <= 0
}

// Copies the rows of `area` from `image` into `bytes`, top row first.
func readArea(image: Image, area: Area, bytes: *Array'u8)
{
    let rowBytes = cast(u64, area.w * image.bytesPerPixel)
    bytes.resize(rowBytes * cast(u64, area.h))

    let source = image.pixels.storage()
    let target = bytes.storage()
    for row in area.h
    {
        let bufferRow = image.height - 1 - (area.y + row)
        let from      = source + cast(u64, bufferRow * image.rowStride + area.x * image.bytesPerPixel)
        Memory.copy(target + cast(u64, row) * rowBytes, from, rowBytes)
    }
}

// Copies `bytes`, rows of `area` top row first, into `image`.
func writeArea(image: *Image, area: Area, bytes: const [..] u8)
{
    let rowBytes = cast(u64, area.w * image.bytesPerPixel)
    Swag.assert(bytes.count == rowBytes * cast(u64, area.h))

    let target = image.pixels.storage()
    for row in area.h
    {
        let bufferRow = image.height - 1 - (area.y + row)
        let into      = target + cast(u64, bufferRow * image.rowStride + area.x * image.bytesPerPixel)
        Memory.copy(into, bytes.buffer + cast(u64, row) * rowBytes, rowBytes)
    }
}
