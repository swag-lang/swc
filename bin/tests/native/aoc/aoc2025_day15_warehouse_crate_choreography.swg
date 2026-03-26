#global fileprivate

// Real-life example: simulate a warehouse robot that pushes chains of narrow
// crates and compute the final GPS-style stock location sum.

const MaxWarehouseCells = 256

struct WarehouseReport
{
    successfulPushes: u32
    gpsSum:           u64
}

func lineWidth(line: string)->u32
{
    return cast(u32) @countof(cast(const [..] u8) line)
}

func cellIndex(x, y, width: u32)->u32
{
    return y * width + x
}

func moveDelta(outDx: *s32, outDy: *s32, instruction: u8)
{
    switch instruction
    {
        case '<''u8:
            dref outDx = -1
            dref outDy = 0
            break

        case '>''u8:
            dref outDx = 1
            dref outDy = 0
            break

        case '^''u8:
            dref outDx = 0
            dref outDy = -1
            break

        case 'v''u8:
            dref outDx = 0
            dref outDy = 1
            break

        default:
            @assert(false)
            break
    }
}

func simulateWarehouse(layout: const [..] string, instructions: string)->WarehouseReport
{
    let height = cast(u32) @countof(layout)
    let width = lineWidth(layout[0])
    let totalCells = width * height

    @assert(totalCells <= MaxWarehouseCells)

    var cells: [MaxWarehouseCells] u8
    var robotX: s32
    var robotY: s32

    foreach _, rowIndex in layout
    {
        @assert(lineWidth(layout[rowIndex]) == width)

        let row = cast(const [..] u8) layout[rowIndex]
        for width
        {
            let x = cast(u32) @index
            let src = row[x]
            let index = cellIndex(x, cast(u32) rowIndex, width)

            if src == '@''u8
            {
                robotX = cast(s32) x
                robotY = cast(s32) rowIndex
                cells[index] = '.''u8
            }
            else
            {
                cells[index] = src
            }
        }
    }

    let moveBytes = cast(const [..] u8) instructions
    var result: WarehouseReport

    foreach instruction in moveBytes
    {
        var dx: s32
        var dy: s32
        moveDelta(&dx, &dy, instruction)

        let nextX = robotX + dx
        let nextY = robotY + dy
        let nextIndex = cellIndex(cast(u32) nextX, cast(u32) nextY, width)
        let nextCell = cells[nextIndex]

        if nextCell == '#''u8 do
            continue

        if nextCell == '.''u8
        {
            robotX = nextX
            robotY = nextY
            continue
        }

        @assert(nextCell == 'O''u8)

        var scanX = nextX
        var scanY = nextY
        var scanIndex = nextIndex

        while cells[scanIndex] == 'O''u8
        {
            scanX += dx
            scanY += dy
            scanIndex = cellIndex(cast(u32) scanX, cast(u32) scanY, width)
        }

        if cells[scanIndex] == '#''u8 do
            continue

        while scanX != nextX or scanY != nextY
        {
            let prevX = scanX - dx
            let prevY = scanY - dy
            let prevIndex = cellIndex(cast(u32) prevX, cast(u32) prevY, width)

            cells[scanIndex] = cells[prevIndex]
            scanX = prevX
            scanY = prevY
            scanIndex = prevIndex
        }

        cells[nextIndex] = '.''u8
        robotX = nextX
        robotY = nextY
        result.successfulPushes += 1
    }

    for totalCells
    {
        if cells[@index] == 'O''u8
        {
            let x = cast(u64) (@index % width)
            let y = cast(u64) (@index / width)
            result.gpsSum += y * 100'u64 + x
        }
    }

    return result
}

#test
{
    const sampleLayout: [8] string =
    [
        "########",
        "#..O.O.#",
        "##@.O..#",
        "#...O..#",
        "#.#.O..#",
        "#...O..#",
        "#......#",
        "########",
    ]

    let sampleReport = simulateWarehouse(sampleLayout, "<^^>>>vv<v>>v<<")

    @assert(sampleReport.successfulPushes == 6'u32)
    @assert(sampleReport.gpsSum == 2028'u64)

    let secondReport = simulateWarehouse(sampleLayout, ">v>v<<^>>vv<^")

    @assert(secondReport.successfulPushes == 4'u32)
    @assert(secondReport.gpsSum == 1825'u64)

    const compactLayout: [6] string =
    [
        "#######",
        "#@OO..#",
        "#..#..#",
        "#..O..#",
        "#.....#",
        "#######",
    ]

    let compactReport = simulateWarehouse(compactLayout, ">>>v<<")

    @assert(compactReport.successfulPushes == 2'u32)
    @assert(compactReport.gpsSum == 512'u64)
}
