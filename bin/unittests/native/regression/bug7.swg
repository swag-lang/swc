#global fileprivate

struct InlineRectangle
{
    x:      f32
    y:      f32
    width:  f32
    height: f32
}

impl InlineRectangle
{
    #[Swag.Inline]
    mtd const opCompare(other: const &InlineRectangle)->s32
    {
        let swagCmp0 = .x <=> other.x
        if swagCmp0 != 0 do
            return swagCmp0

        let swagCmp1 = .y <=> other.y
        if swagCmp1 != 0 do
            return swagCmp1

        let swagCmp2 = .width <=> other.width
        if swagCmp2 != 0 do
            return swagCmp2

        let swagCmp3 = .height <=> other.height
        if swagCmp3 != 0 do
            return swagCmp3

        return 0
    }

    #[Swag.Inline]
    mtd const opEquals(other: const &InlineRectangle)->bool
    {
        return .x == other.x and .y == other.y and .width == other.width and .height == other.height
    }
}

func inlineRectanglePick(a, b, c: InlineRectangle)->f32
{
    var result = 0'f32

    if a == b do
        result += 1
    if a != c do
        result += 2
    if a < c do
        result += 4
    if c > b do
        result += 8
    if a <= b do
        result += 16
    if c >= a do
        result += 32

    return result
}

func inlineRectanglePickDirect(a, b, c: InlineRectangle)->f32
{
    var result = 0'f32

    if a.opEquals(b) do
        result += 1
    if !a.opEquals(c) do
        result += 2
    if a.opCompare(c) < 0 do
        result += 4
    if c.opCompare(b) > 0 do
        result += 8
    if a.opCompare(b) <= 0 do
        result += 16
    if c.opCompare(a) >= 0 do
        result += 32

    return result
}

func inlineRectangleLess(a, c: InlineRectangle)->bool
{
    return a < c
}

func inlineRectangleCompare(a, c: InlineRectangle)->s32
{
    return a.opCompare(c)
}

#test
{
    var a = InlineRectangle{1, 2, 3, 4}
    var b = InlineRectangle{1, 2, 3, 4}
    var c = InlineRectangle{1, 2, 4, 4}

    @assert(inlineRectanglePick(a, b, c) == 63)
    @assert(inlineRectanglePickDirect(a, b, c) == 63)
    @assert(inlineRectangleLess(a, c))
    @assert(inlineRectangleCompare(a, c) == -1)
    @assert(a == b)
    @assert(a != c)
    @assert(a < c)
    @assert(c > b)
    @assert(a <= b)
    @assert(c >= a)
}
