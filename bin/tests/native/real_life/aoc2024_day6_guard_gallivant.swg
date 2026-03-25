#global fileprivate

// Advent of Code 2024 Day 6: simulate the guard path with heap-allocated
// storage and explicit cleanup through defer.

const InitialTraceCapacity = 2'u32

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
    cells:  [*] u8
}

struct IndexBuffer
{
    data:      [*] u32
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
    return ch == '\n''u8 or ch == '\r''u8
}

func cellIndex(x, y, width: u32)->u32
{
    return y * width + x
}

func allocBytes(size: u32)->[*] u8
{
    let ptr = cast([*] u8) @alloc(cast(u64) size)
    @assert(ptr != null)
    return ptr
}

func zeroBytes(ptr: [*] u8, count: u32)
{
    for count
    {
        ptr[cast(u32) @index] = 0'u8
    }
}

func freeGrid(grid: GridMap)
{
    if grid.cells do
        @free(grid.cells)
}

func freeIndexBuffer(buffer: IndexBuffer)
{
    if buffer.data do
        @free(buffer.data)
}

func initIndexBuffer(initialCapacity: u32)->IndexBuffer
{
    var result: IndexBuffer
    result.capacity = initialCapacity
    result.data = cast([*] u32) @alloc(cast(u64) initialCapacity * cast(u64) #sizeof(u32))
    @assert(result.data != null)
    return result
}

func appendIndex(buffer: IndexBuffer, value: u32)->IndexBuffer
{
    var result = buffer

    if result.count == result.capacity
    {
        let newCapacity = result.capacity * 2'u32
        result.data = cast([*] u32) @realloc(result.data, cast(u64) newCapacity * cast(u64) #sizeof(u32))
        @assert(result.data != null)
        result.capacity = newCapacity
        result.growCount += 1'u32
    }

    result.data[result.count] = value
    result.count += 1'u32
    return result
}

func turnRight(dir: Direction)->Direction
{
    #[Swag.Complete]
    switch dir
    {
    case Direction.Up:    return Direction.Right
    case Direction.Right: return Direction.Down
    case Direction.Down:  return Direction.Left
    case Direction.Left:  return Direction.Up
    }

    return Direction.Up
}

func directionDelta(outDx: *s32, outDy: *s32, dir: Direction)
{
    #[Swag.Complete]
    switch dir
    {
    case Direction.Up:
        dref outDx = 0
        dref outDy = -1
        break

    case Direction.Right:
        dref outDx = 1
        dref outDy = 0
        break

    case Direction.Down:
        dref outDx = 0
        dref outDy = 1
        break

    case Direction.Left:
        dref outDx = -1
        dref outDy = 0
        break
    }
}

func inBounds(x, y: s32, grid: GridMap)->bool
{
    return x >= 0 and y >= 0 and cast(u32) x < grid.width and cast(u32) y < grid.height
}

func parseGrid(outGrid: *GridMap, text: string)
{
    let bytes = cast(const [..] u8) text

    var width: u32
    while width < @countof(bytes) and !isLineBreak(bytes[width])
    {
        width += 1
    }

    var height: u32
    var lineWidth: u32
    for @countof(bytes)
    {
        let ch = bytes[@index]
        if isLineBreak(ch)
        {
            if lineWidth != 0
            {
                @assert(lineWidth == width)
                height += 1'u32
                lineWidth = 0
            }

            continue
        }

        lineWidth += 1'u32
    }

    if lineWidth != 0
    {
        @assert(lineWidth == width)
        height += 1'u32
    }

    var result: GridMap
    result.width = width
    result.height = height
    result.cells = allocBytes(width * height)

    var x: u32
    var y: u32
    for @countof(bytes)
    {
        let ch = bytes[@index]
        if isLineBreak(ch) do
            continue

        let writeIndex = cellIndex(x, y, width)
        if ch == '^''u8
        {
            result.startX = x
            result.startY = y
            result.cells[writeIndex] = '.''u8
        }
        else
        {
            result.cells[writeIndex] = ch
        }

        x += 1'u32
        if x == width
        {
            x = 0
            y += 1'u32
        }
    }

    dref outGrid = result
}

func collectVisitedTrace(outVisitedCount: *u32, outTrace: *IndexBuffer, grid: GridMap)
{
    let cellCount = grid.width * grid.height
    let visited = allocBytes(cellCount)
    defer @free(visited)
    zeroBytes(visited, cellCount)

    let seenStates = allocBytes(cellCount * 4'u32)
    defer @free(seenStates)
    zeroBytes(seenStates, cellCount * 4'u32)

    var trace = initIndexBuffer(InitialTraceCapacity)

    var x = cast(s32) grid.startX
    var y = cast(s32) grid.startY
    var dir = Direction.Up

    let startIndex = cellIndex(grid.startX, grid.startY, grid.width)
    visited[startIndex] = 1'u8
    dref outVisitedCount = 1'u32
    trace = appendIndex(trace, startIndex)

    while true
    {
        let stateIndex = cellIndex(cast(u32) x, cast(u32) y, grid.width) * 4'u32 + cast(u32) dir
        @assert(seenStates[stateIndex] == 0'u8)
        seenStates[stateIndex] = 1'u8

        var dx, dy: s32
        directionDelta(&dx, &dy, dir)

        let nextX = x + dx
        let nextY = y + dy
        if !inBounds(nextX, nextY, grid) do
            break

        let nextIndex = cellIndex(cast(u32) nextX, cast(u32) nextY, grid.width)
        if grid.cells[nextIndex] == '#''u8
        {
            dir = turnRight(dir)
            continue
        }

        x = nextX
        y = nextY
        if visited[nextIndex] == 0'u8
        {
            visited[nextIndex] = 1'u8
            dref outVisitedCount += 1'u32
            trace = appendIndex(trace, nextIndex)
        }
    }

    dref outTrace = trace
}

func doesObstacleCauseLoop(grid: GridMap, obstacleIndex: u32)->bool
{
    let cellCount = grid.width * grid.height
    let seenStates = allocBytes(cellCount * 4'u32)
    defer @free(seenStates)
    zeroBytes(seenStates, cellCount * 4'u32)

    var x = cast(s32) grid.startX
    var y = cast(s32) grid.startY
    var dir = Direction.Up

    while true
    {
        let stateIndex = cellIndex(cast(u32) x, cast(u32) y, grid.width) * 4'u32 + cast(u32) dir
        if seenStates[stateIndex] != 0'u8 do
            return true

        seenStates[stateIndex] = 1'u8

        var dx, dy: s32
        directionDelta(&dx, &dy, dir)

        let nextX = x + dx
        let nextY = y + dy
        if !inBounds(nextX, nextY, grid) do
            return false

        let nextIndex = cellIndex(cast(u32) nextX, cast(u32) nextY, grid.width)
        if nextIndex == obstacleIndex or grid.cells[nextIndex] == '#''u8
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

    for trace.count
    {
        let obstacleIndex = trace.data[cast(u32) @index]
        if obstacleIndex == startIndex do
            continue

        if doesObstacleCauseLoop(grid, obstacleIndex) do
            result += 1'u32
    }

    return result
}

func auditPatrol(text: string)->PatrolReport
{
    var grid: GridMap
    parseGrid(&grid, text)
    defer freeGrid(grid)

    var visitedCount: u32
    var trace: IndexBuffer
    collectVisitedTrace(&visitedCount, &trace, grid)
    defer freeIndexBuffer(trace)

    var result: PatrolReport
    result.visitedCount = visitedCount
    result.traceCapacity = trace.capacity
    result.reallocCount = trace.growCount
    result.loopObstacleCount = countLoopObstacles(grid, trace)
    return result
}

#test
{
    let sample = auditPatrol(SampleInput)

    @assert(sample.visitedCount == 41'u32)
    @assert(sample.loopObstacleCount == 6'u32)
    @assert(sample.traceCapacity == 64'u32)
    @assert(sample.reallocCount == 5'u32)
}

#test
{
    let coverage = auditPatrol(CoverageInput)

    @assert(coverage.visitedCount == 3'u32)
    @assert(coverage.loopObstacleCount == 0'u32)
    @assert(coverage.traceCapacity == 4'u32)
    @assert(coverage.reallocCount == 1'u32)
}
