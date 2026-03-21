#global fileprivate

// Real-life example: audit how many maintenance tunnel shortcuts would save a
// meaningful amount of time with either short hops or long emergency passes.

const MaxTrackCells = 512

struct ShortcutReport
{
    shortCheatCount: u32
    longCheatCount:  u32
}

func lineWidth(line: string)->u32
{
    return cast(u32) @countof(cast(const [..] u8) line)
}

func cellIndex(x, y, width: u32)->u32
{
    return y * width + x
}

func absDiff(a, b: u32)->u32
{
    if a > b do
        return a - b
    return b - a
}

func countCheats(layout: const [..] string, maxCheatLength, minSaving: u32)->u32
{
    let height = cast(u32) @countof(layout)
    let width = lineWidth(layout[0])
    let totalCells = width * height
    @assert(totalCells <= MaxTrackCells)

    var startCell: u32
    var endCell: u32
    var walkable: [MaxTrackCells] bool
    var distFromStart: [MaxTrackCells] u32
    var distFromEnd: [MaxTrackCells] u32
    var queue: [MaxTrackCells] u32

    foreach _, rowIndex in layout
    {
        @assert(lineWidth(layout[rowIndex]) == width)
        let row = cast(const [..] u8) layout[rowIndex]

        for width
        {
            let x = cast(u32) @index
            let index = cellIndex(x, cast(u32) rowIndex, width)
            let cell = row[x]

            walkable[index] = cell != '#''u8
            distFromStart[index] = Swag.U32.Max
            distFromEnd[index] = Swag.U32.Max
            if cell == 'S''u8 do
                startCell = index
            if cell == 'E''u8 do
                endCell = index
        }
    }

    var head: u32
    var tail: u32

    distFromStart[startCell] = 0
    queue[tail] = startCell
    tail += 1

    while head < tail
    {
        let current = queue[head]
        head += 1

        let x = current % width
        let y = current / width
        let nextDistance = distFromStart[current] + 1

        if x > 0
        {
            let nextCell = cellIndex(x - 1, y, width)
            if walkable[nextCell] and distFromStart[nextCell] == Swag.U32.Max
            {
                distFromStart[nextCell] = nextDistance
                queue[tail] = nextCell
                tail += 1
            }
        }

        if x + 1 < width
        {
            let nextCell = cellIndex(x + 1, y, width)
            if walkable[nextCell] and distFromStart[nextCell] == Swag.U32.Max
            {
                distFromStart[nextCell] = nextDistance
                queue[tail] = nextCell
                tail += 1
            }
        }

        if y > 0
        {
            let nextCell = cellIndex(x, y - 1, width)
            if walkable[nextCell] and distFromStart[nextCell] == Swag.U32.Max
            {
                distFromStart[nextCell] = nextDistance
                queue[tail] = nextCell
                tail += 1
            }
        }

        if y + 1 < height
        {
            let nextCell = cellIndex(x, y + 1, width)
            if walkable[nextCell] and distFromStart[nextCell] == Swag.U32.Max
            {
                distFromStart[nextCell] = nextDistance
                queue[tail] = nextCell
                tail += 1
            }
        }
    }

    head = 0
    tail = 0
    distFromEnd[endCell] = 0
    queue[tail] = endCell
    tail += 1

    while head < tail
    {
        let current = queue[head]
        head += 1

        let x = current % width
        let y = current / width
        let nextDistance = distFromEnd[current] + 1

        if x > 0
        {
            let nextCell = cellIndex(x - 1, y, width)
            if walkable[nextCell] and distFromEnd[nextCell] == Swag.U32.Max
            {
                distFromEnd[nextCell] = nextDistance
                queue[tail] = nextCell
                tail += 1
            }
        }

        if x + 1 < width
        {
            let nextCell = cellIndex(x + 1, y, width)
            if walkable[nextCell] and distFromEnd[nextCell] == Swag.U32.Max
            {
                distFromEnd[nextCell] = nextDistance
                queue[tail] = nextCell
                tail += 1
            }
        }

        if y > 0
        {
            let nextCell = cellIndex(x, y - 1, width)
            if walkable[nextCell] and distFromEnd[nextCell] == Swag.U32.Max
            {
                distFromEnd[nextCell] = nextDistance
                queue[tail] = nextCell
                tail += 1
            }
        }

        if y + 1 < height
        {
            let nextCell = cellIndex(x, y + 1, width)
            if walkable[nextCell] and distFromEnd[nextCell] == Swag.U32.Max
            {
                distFromEnd[nextCell] = nextDistance
                queue[tail] = nextCell
                tail += 1
            }
        }
    }

    let baseDistance = distFromStart[endCell]
    var result: u32

    for totalCells
    {
        let fromCell = cast(u32) @index
        if !walkable[fromCell] or distFromStart[fromCell] == Swag.U32.Max do
            continue

        let fromX = fromCell % width
        let fromY = fromCell / width

        for totalCells
        {
            let toCell = cast(u32) @index
            if !walkable[toCell] or distFromEnd[toCell] == Swag.U32.Max do
                continue

            let cheatLength = absDiff(fromX, toCell % width) + absDiff(fromY, toCell / width)
            if cheatLength == 0 or cheatLength > maxCheatLength do
                continue

            let cheatedDistance = distFromStart[fromCell] + cheatLength + distFromEnd[toCell]
            if cheatedDistance + minSaving <= baseDistance do
                result += 1
        }
    }

    return result
}

func analyzeShortcuts(layout: const [..] string)->ShortcutReport
{
    var result: ShortcutReport
    result.shortCheatCount = countCheats(layout, 2, 20)
    result.longCheatCount = countCheats(layout, 20, 50)
    return result
}

#test
{
    const sampleMap: [15] string =
    [
        "###############",
        "#...#...#.....#",
        "#.#.#.#.#.###.#",
        "#S#...#.#.#...#",
        "#######.#.#.###",
        "#######.#.#...#",
        "#######.#.###.#",
        "###..E#...#...#",
        "###.#######.###",
        "#...###...#...#",
        "#.#####.#.###.#",
        "#.#...#.#.#...#",
        "#.#.#.#.#.#.###",
        "#...#...#...###",
        "###############",
    ]

    let sampleReport = analyzeShortcuts(sampleMap)

    @assert(sampleReport.shortCheatCount == 5)
    @assert(sampleReport.longCheatCount == 285)
}
