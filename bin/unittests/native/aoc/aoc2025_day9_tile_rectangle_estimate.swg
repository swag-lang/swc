#global private

// Real-life example: estimate the largest rectangular tile replacement zone
// using any two marked corner tiles from a floor survey.

struct Point2
{
    x: u32
    y: u32
}

struct RectangleEstimate
{
    pointCount: u32
    bestArea:   u64
    bestLeft:   u32
    bestRight:  u32
    bestTop:    u32
    bestBottom: u32
}

func absDiff(lhs, rhs: u32)->u32
{
    return lhs > rhs ? lhs - rhs : rhs - lhs
}

func parseNumber(bytes: const [..] u8, index: *u32)->u32
{
    var result: u32

    while index[] < bytes.count and bytes[index[]] >= '0' and bytes[index[]] <= '9'
    {
        result  = result * 10'u32 + cast(u32) (bytes[index[]] - '0')
        index[] += 1
    }

    return result
}

func parsePoint(text: string)->Point2
{
    let bytes = cast(const [..] u8) text

    var index:  u32
    var result: Point2

    result.x = parseNumber(bytes, &index)
    index    += 1
    result.y = parseNumber(bytes, &index)
    return result
}

func estimateReplacementArea(pointLines: const [..] string)->RectangleEstimate
{
    Swag.assert(pointLines.count > 1)
    Swag.assert(pointLines.count <= 24)

    var points: [24] Point2
    var result: RectangleEstimate

    for line, index in pointLines
    {
        points[index] = parsePoint(line)
    }

    result.pointCount = cast(u32) pointLines.count

    for lhs in pointLines.count
    {
        if cast(u32) lhs + 1 >= pointLines.count do
            continue

        for rhs in cast(u32) lhs + 1 to pointLines.count - 1
        {
            let a      = points[lhs]
            let b      = points[rhs]
            let width  = cast(u64) absDiff(a.x, b.x) + 1'u64
            let height = cast(u64) absDiff(a.y, b.y) + 1'u64
            let area   = width * height

            if area > result.bestArea
            {
                result.bestArea   = area
                result.bestLeft   = a.x < b.x ? a.x : b.x
                result.bestRight  = a.x > b.x ? a.x : b.x
                result.bestTop    = a.y < b.y ? a.y : b.y
                result.bestBottom = a.y > b.y ? a.y : b.y
            }
        }
    }

    return result
}

#test
{
    const sampleTiles: [8] string =
        [
        "7,1",
        "11,1",
        "11,7",
        "9,7",
        "9,5",
        "2,5",
        "2,3",
        "7,3"
        ]

    let sampleEstimate = estimateReplacementArea(sampleTiles)

    Swag.assert(sampleEstimate.pointCount == 8'u32)
    Swag.assert(sampleEstimate.bestArea == 50'u64)
    Swag.assert(sampleEstimate.bestLeft == 2'u32)
    Swag.assert(sampleEstimate.bestRight == 11'u32)
    Swag.assert(sampleEstimate.bestTop == 1'u32)
    Swag.assert(sampleEstimate.bestBottom == 5'u32)

    const lobbyTiles: [6] string =
        [
        "3,2",
        "8,2",
        "8,6",
        "4,9",
        "1,9",
        "1,4"
        ]

    let lobbyEstimate = estimateReplacementArea(lobbyTiles)

    Swag.assert(lobbyEstimate.pointCount == 6'u32)
    Swag.assert(lobbyEstimate.bestArea == 64'u64)
    Swag.assert(lobbyEstimate.bestLeft == 1'u32)
    Swag.assert(lobbyEstimate.bestRight == 8'u32)
    Swag.assert(lobbyEstimate.bestTop == 2'u32)
    Swag.assert(lobbyEstimate.bestBottom == 9'u32)
}
