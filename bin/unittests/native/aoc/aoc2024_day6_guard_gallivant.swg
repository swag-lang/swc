#global private

// Advent of Code 2024 Day 6: simulate the guard path with heap-allocated
// storage and explicit cleanup through defer.

const InitialTraceCapacity = 2_u32

const SampleInput =
    """....#.....
.........#
..........
..#.......
.......#..
..........
.#..^.....
........#.
#.........
......#..."""

const CoverageInput =
    """.....
..#..
.^...
.....
....."""

enum Direction: u8
{
    Up
    Right
    Down
    Left
}

struct GridMap
{
    width:  u32
    height: u32
    startX: u32
    startY: u32
    cells:  [*] u8?
}

struct IndexBuffer
{
    data:      [*] u32?
    count:     u32
    capacity:  u32
    growCount: u32
}

struct PatrolReport
{
    visitedCount:      u32
    loopObstacleCount: u32
    traceCapacity:     u32
    reallocCount:      u32
}

func isLineBreak(ch: u8)->bool
{
    return ch == '\n'_u8 or ch == '\r'_u8
}

func cellIndex(x, y, width: u32)->u32
{
    return y * width + x
}

func allocBytes(size: u32)->[*] u8
{
    let ptr = cast([*] u8?, testAlloc(cast(u64, size)))
    Swag.assert(ptr != null)
    return ptr
}

func zeroBytes(ptr: [*] u8, count: u32)
{
    for index in count
    {
        ptr[cast(u32, index)] = 0_u8
    }
}

func freeGrid(grid: GridMap)
{
    if grid.cells
    {
        testFree(grid.cells)
    }
}

func freeIndexBuffer(buffer: IndexBuffer)
{
    if buffer.data
    {
        testFree(buffer.data)
    }
}

func initIndexBuffer(initialCapacity: u32)->IndexBuffer
{
    var result: IndexBuffer
    result.capacity = initialCapacity
    result.data     = cast([*] u32?, testAlloc(cast(u64, initialCapacity) * cast(u64, #sizeof(u32))))
    Swag.assert(result.data != null)
    return result
}

func appendIndex(buffer: IndexBuffer, value: u32)->IndexBuffer
{
    var result = buffer

    if result.count == result.capacity
    {
        let newCapacity = result.capacity * 2_u32
        result.data = cast([*] u32?, testRealloc(result.data, cast(u64, newCapacity) * cast(u64, #sizeof(u32))))
        Swag.assert(result.data != null)
        result.capacity  = newCapacity
        result.growCount += 1_u32
    }

    let data = unwrap result.data
    data[result.count] = value
    result.count       += 1_u32
    return result
}

func turnRight(dir: Direction)->Direction
{
    switch #complete dir
    {
    case Direction.Up:    return Direction.Right
    case Direction.Right: return Direction.Down
    case Direction.Down:  return Direction.Left
    case Direction.Left:  return Direction.Up
    }
}

func directionDelta(outDx: *s32, outDy: *s32, dir: Direction)
{
    switch #complete dir
    {
    case Direction.Up:
        outDx[] = 0
        outDy[] = -1
        break

    case Direction.Right:
        outDx[] = 1
        outDy[] = 0
        break

    case Direction.Down:
        outDx[] = 0
        outDy[] = 1
        break

    case Direction.Left:
        outDx[] = -1
        outDy[] = 0
        break
    }
}

func inBounds(x, y: s32, grid: GridMap)->bool
{
    return x >= 0 and y >= 0 and cast(u32, x) < grid.width and cast(u32, y) < grid.height
}

func parseGrid(outGrid: *GridMap, text: string)
{
    let bytes = cast(const [..] u8, text)

    var width: u32
    while width < bytes.count and not isLineBreak(bytes[width])
    {
        width += 1
    }

    var height:    u32
    var lineWidth: u32
    for index in bytes.count
    {
        let ch = bytes[index]
        if isLineBreak(ch)
        {
            if lineWidth != 0
            {
                Swag.assert(lineWidth == width)
                height    += 1_u32
                lineWidth = 0
            }

            continue
        }

        lineWidth += 1_u32
    }

    if lineWidth != 0
    {
        Swag.assert(lineWidth == width)
        height += 1_u32
    }

    var result: GridMap
    result.width  = width
    result.height = height
    result.cells  = allocBytes(width * height)

    var x: u32
    var y: u32
    for index in bytes.count
    {
        let ch = bytes[index]
        if isLineBreak(ch)
        {
            continue
        }

        let writeIndex = cellIndex(x, y, width)
        if ch == '^'_u8
        {
            result.startX = x
            result.startY = y
            result.cells[writeIndex] = '.'_u8
        }
        else
        {
            result.cells[writeIndex] = ch
        }

        x += 1_u32
        if x == width
        {
            x = 0
            y += 1_u32
        }
    }

    outGrid[] = result
}

func collectVisitedTrace(outVisitedCount: *u32, outTrace: *IndexBuffer, grid: GridMap)
{
    let cellCount = grid.width * grid.height
    let visited   = allocBytes(cellCount)
    defer testFree(visited)
    zeroBytes(visited, cellCount)

    let seenStates = allocBytes(cellCount * 4_u32)
    defer testFree(seenStates)
    zeroBytes(seenStates, cellCount * 4_u32)

    var trace = initIndexBuffer(InitialTraceCapacity)

    var x   = cast(s32, grid.startX)
    var y   = cast(s32, grid.startY)
    var dir = Direction.Up

    let startIndex = cellIndex(grid.startX, grid.startY, grid.width)
    visited[startIndex] = 1_u8
    outVisitedCount[]   = 1_u32
    trace = appendIndex(trace, startIndex)

    while true
    {
        let stateIndex = cellIndex(cast(u32, x), cast(u32, y), grid.width) * 4_u32 + cast(u32, dir)
        Swag.assert(seenStates[stateIndex] == 0_u8)
        seenStates[stateIndex] = 1_u8

        var dx, dy: s32
        directionDelta(&dx, &dy, dir)

        let nextX = x + dx
        let nextY = y + dy
        if not inBounds(nextX, nextY, grid)
        {
            break
        }

        let nextIndex = cellIndex(cast(u32, nextX), cast(u32, nextY), grid.width)
        let cells     = unwrap grid.cells
        if cells[nextIndex] == '#'_u8
        {
            dir = turnRight(dir)
            continue
        }

        x = nextX
        y = nextY
        if visited[nextIndex] == 0_u8
        {
            visited[nextIndex] = 1_u8
            outVisitedCount[]  += 1_u32
            trace = appendIndex(trace, nextIndex)
        }
    }

    outTrace[] = trace
}

func doesObstacleCauseLoop(grid: GridMap, obstacleIndex: u32)->bool
{
    let cellCount  = grid.width * grid.height
    let seenStates = allocBytes(cellCount * 4_u32)
    defer testFree(seenStates)
    zeroBytes(seenStates, cellCount * 4_u32)

    var x   = cast(s32, grid.startX)
    var y   = cast(s32, grid.startY)
    var dir = Direction.Up

    while true
    {
        let stateIndex = cellIndex(cast(u32, x), cast(u32, y), grid.width) * 4_u32 + cast(u32, dir)
        if seenStates[stateIndex] != 0_u8
        {
            return true
        }

        seenStates[stateIndex] = 1_u8

        var dx, dy: s32
        directionDelta(&dx, &dy, dir)

        let nextX = x + dx
        let nextY = y + dy
        if not inBounds(nextX, nextY, grid)
        {
            return false
        }

        let nextIndex = cellIndex(cast(u32, nextX), cast(u32, nextY), grid.width)
        let cells     = unwrap grid.cells
        if nextIndex == obstacleIndex or cells[nextIndex] == '#'_u8
        {
            dir = turnRight(dir)
            continue
        }

        x = nextX
        y = nextY
    }

    return false
}

func countLoopObstacles(grid: GridMap, trace: IndexBuffer)->u32
{
    var result: u32
    let startIndex = cellIndex(grid.startX, grid.startY, grid.width)
    let data       = unwrap trace.data

    for index in trace.count
    {
        let obstacleIndex = data[cast(u32, index)]
        if obstacleIndex == startIndex
        {
            continue
        }

        if doesObstacleCauseLoop(grid, obstacleIndex)
        {
            result += 1_u32
        }
    }

    return result
}

func auditPatrol(text: string)->PatrolReport
{
    var grid: GridMap
    parseGrid(&grid, text)
    defer freeGrid(grid)

    var visitedCount: u32
    var trace:        IndexBuffer
    collectVisitedTrace(&visitedCount, &trace, grid)
    defer freeIndexBuffer(trace)

    var result: PatrolReport
    result.visitedCount      = visitedCount
    result.traceCapacity     = trace.capacity
    result.reallocCount      = trace.growCount
    result.loopObstacleCount = countLoopObstacles(grid, trace)
    return result
}

#test
{
    let sample = auditPatrol(SampleInput)

    Swag.require(sample.visitedCount == 41_u32)
    Swag.require(sample.loopObstacleCount == 6_u32)
    Swag.require(sample.traceCapacity == 64_u32)
    Swag.require(sample.reallocCount == 5_u32)
}

#test
{
    let coverage = auditPatrol(CoverageInput)

    Swag.require(coverage.visitedCount == 3_u32)
    Swag.require(coverage.loopObstacleCount == 0_u32)
    Swag.require(coverage.traceCapacity == 4_u32)
    Swag.require(coverage.reallocCount == 1_u32)
}
