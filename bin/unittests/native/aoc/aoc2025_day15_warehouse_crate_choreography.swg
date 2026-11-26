#global private

// Real-life example: simulate a warehouse robot that pushes chains of narrow
// crates and compute the final GPS-style stock location sum.

const MaxWarehouseCells = 256

struct WarehouseReport
{
    successfulPushes: u32
    gpsSum: u64
}

func lineWidth(line: string)->u32
{
    return cast(u32, cast(const [..] u8, line).count)
}

func cellIndex(x, y, width: u32)->u32
{
    return y * width + x
}

func moveDelta(outDx: *s32, outDy: *s32, instruction: u8)
{
    switch instruction
    {
    case '<'_u8:
        outDx[] = -1
        outDy[] = 0
        break

    case '>'_u8:
        outDx[] = 1
        outDy[] = 0
        break

    case '^'_u8:
        outDx[] = 0
        outDy[] = -1
        break

    case 'v'_u8:
        outDx[] = 0
        outDy[] = 1
        break

    default:
        Swag.assert(false)
        break
    }
}

func simulateWarehouse(layout: const [..] string, instructions: string)->WarehouseReport
{
    let height     = cast(u32, layout.count)
    let width      = lineWidth(layout[0])
    let totalCells = width * height

    Swag.assert(totalCells <= MaxWarehouseCells)

    var cells:  [MaxWarehouseCells] u8
    var robotX: s32
    var robotY: s32

    for _, rowIndex in layout
    {
        Swag.assert(lineWidth(layout[rowIndex]) == width)

        let row = cast(const [..] u8, layout[rowIndex])
        for idx in width
        {
            let x     = cast(u32, idx)
            let src   = row[x]
            let index = cellIndex(x, cast(u32, rowIndex), width)

            if src == '@'_u8
            {
                robotX       = cast(s32, x)
                robotY       = cast(s32, rowIndex)
                cells[index] = '.'_u8
            }
            else
            {
                cells[index] = src
            }
        }
    }

    let moveBytes = cast(const [..] u8, instructions)
    var result: WarehouseReport

    for instruction in moveBytes
    {
        var dx: s32
        var dy: s32
        moveDelta(&dx, &dy, instruction)

        let nextX     = robotX + dx
        let nextY     = robotY + dy
        let nextIndex = cellIndex(cast(u32, nextX), cast(u32, nextY), width)
        let nextCell  = cells[nextIndex]

        if nextCell == '#'_u8
        {
            continue
        }

        if nextCell == '.'_u8
        {
            robotX = nextX
            robotY = nextY
            continue
        }

        Swag.assert(nextCell == 'O'_u8)

        var scanX     = nextX
        var scanY     = nextY
        var scanIndex = nextIndex

        while cells[scanIndex] == 'O'_u8
        {
            scanX     += dx
            scanY     += dy
            scanIndex = cellIndex(cast(u32, scanX), cast(u32, scanY), width)
        }

        if cells[scanIndex] == '#'_u8
        {
            continue
        }

        while scanX != nextX or scanY != nextY
        {
            let prevX     = scanX - dx
            let prevY     = scanY - dy
            let prevIndex = cellIndex(cast(u32, prevX), cast(u32, prevY), width)

            cells[scanIndex] = cells[prevIndex]
            scanX            = prevX
            scanY            = prevY
            scanIndex        = prevIndex
        }

        cells[nextIndex]        = '.'_u8
        robotX                  = nextX
        robotY                  = nextY
        result.successfulPushes += 1
    }

    for idx in totalCells
    {
        if cells[idx] == 'O'_u8
        {
            let x = cast(u64, (idx % width))
            let y = cast(u64, (idx / width))
            result.gpsSum += y * 100_u64 + x
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
        "########"
        ]

    let sampleReport = simulateWarehouse(sampleLayout, "<^^>>>vv<v>>v<<")

    Swag.require(sampleReport.successfulPushes == 6_u32)
    Swag.require(sampleReport.gpsSum == 2028_u64)

    let secondReport = simulateWarehouse(sampleLayout, ">v>v<<^>>vv<^")

    Swag.require(secondReport.successfulPushes == 4_u32)
    Swag.require(secondReport.gpsSum == 1825_u64)

    const compactLayout: [6] string =
        [
        "#######",
        "#@OO..#",
        "#..#..#",
        "#..O..#",
        "#.....#",
        "#######"
        ]

    let compactReport = simulateWarehouse(compactLayout, ">>>v<<")

    Swag.require(compactReport.successfulPushes == 2_u32)
    Swag.require(compactReport.gpsSum == 512_u64)
}
