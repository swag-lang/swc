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

func withLibrary(cb: func||(FT_Library))
{
    var library: FT_Library
    discard catch FT_Init_FreeType(&library)
    @assert(@err == null)
    defer catch FT_Done_FreeType(library)
    cb(library)
}

func withFace(cb: func||(const *Array'u8, FT_Library, FT_Face), fileName: string = "segoeui.ttf")
{
    var library: FT_Library
    discard catch FT_Init_FreeType(&library)
    @assert(@err == null)
    defer catch FT_Done_FreeType(library)

    let bytes = loadFontBytes(fileName)

    var face: FT_Face
    discard catch FT_New_Memory_Face(library, bytes.buffer, cast(FT_Long) bytes.count, 0, &face)
    @assert(@err == null)
    @assert(face != null)
    defer FT_Done_Face(face)

    cb(&bytes, library, face)
}

func getFaceData(face: FT_Face)->*FreeTypePriv.FaceImpl
{
    return cast(*FreeTypePriv.FaceImpl) face.finternal
}

func getOutlineBounds(outline: const *FT_Outline)->FT_BBox
{
    var result: retval
    result.xMin = Swag.S32.Max
    result.yMin = Swag.S32.Max
    result.xMax = Swag.S32.Min
    result.yMax = Swag.S32.Min

    if !outline or outline.n_points <= 0
    {
        result = {}
        return result
    }

    for cast(u32) outline.n_points
    {
        let pt = outline.points[@index]
        result.xMin = Math.min(result.xMin, pt.x)
        result.yMin = Math.min(result.yMin, pt.y)
        result.xMax = Math.max(result.xMax, pt.x)
        result.yMax = Math.max(result.yMax, pt.y)
    }

    return result
}

func countBitmapCoverage(bitmap: const *FT_Bitmap)->u32
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

func findPointWithNonZeroY(outline: const *FT_Outline)->u32
{
    @assert(outline != null)
    for cast(u32) outline.n_points
    {
        if outline.points[@index].y != 0 do
            return @index
    }

    @assert(false)
    return 0
}

func moveToCounter(_: const *FT_Vector, user: *void)->s32
{
    let counter = cast(*OutlineCounter) user
    counter.moves += 1
    return 0
}

func lineToCounter(_: const *FT_Vector, user: *void)->s32
{
    let counter = cast(*OutlineCounter) user
    counter.lines += 1
    return 0
}

func conicToCounter(_: const *FT_Vector, dest: const *FT_Vector, user: *void)->s32
{
    let counter = cast(*OutlineCounter) user
    counter.conics += 1
    return 0
}
