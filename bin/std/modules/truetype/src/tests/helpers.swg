#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

struct OutlineCounter
{
    moves:      u32
    lines:      u32
    conics:     u32
}

func getTestDataPath(fileName: string, loc = #callerlocation)->string
{
    var path = Path.getDirectoryName(loc.fileName)
    path = Path.combine(path, "data")
    path = Path.combine(path, fileName)
    @assert(File.exists(path))
    return path
}

func loadFontBytes(fileName: string = "segoeui.ttf")->Array'u8
{
    let bytes = catch File.readAllBytes(getTestDataPath(fileName))
    @assert(@err == null)
    return bytes
}

struct FaceScope
{
    bytes:       Array'u8
    face:        *Face
}

impl FaceScope
{
    mtd init(fileName: string = "segoeui.ttf")
    {
        .bytes = loadFontBytes(fileName)

        .face = catch Face.load(.bytes.toSlice())
        @assert(@err == null)
        @assert(.face != null)
    }

    mtd opDrop()
    {
        if .face
        {
            .face.destroy()
            .face = null
        }
    }
}

func getFaceData(face: *Face)->*FaceImpl
{
    return cast(*FaceImpl) cast(*void) face
}

func getOutlineBounds(outline: const *Outline)->BBox
{
    var result: retval
    result.xMin = Swag.S32.Max
    result.yMin = Swag.S32.Max
    result.xMax = Swag.S32.Min
    result.yMax = Swag.S32.Min

    if !outline or outline.pointCount <= 0
    {
        result = {}
        return result
    }

    for cast(u32) outline.pointCount
    {
        let pt = outline.points[@index]
        result.xMin = Math.min(result.xMin, pt.x)
        result.yMin = Math.min(result.yMin, pt.y)
        result.xMax = Math.max(result.xMax, pt.x)
        result.yMax = Math.max(result.yMax, pt.y)
    }

    return result
}

func countBitmapCoverage(bitmap: const *Bitmap)->u32
{
    if !bitmap or !bitmap.buffer do
        return 0

    var count = 0'u32
    for cast(u64) bitmap.width * bitmap.rows
    {
        if bitmap.buffer[@index] != 0 do
            count += 1
    }

    return count
}

func findPointWithNonZeroY(outline: const *Outline)->u32
{
    @assert(outline != null)
    for cast(u32) outline.pointCount
    {
        if outline.points[@index].y != 0 do
            return @index
    }

    @assert(false)
    return 0
}
