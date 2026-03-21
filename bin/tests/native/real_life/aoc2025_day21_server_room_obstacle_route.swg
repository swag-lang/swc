#global fileprivate

// Real-life example: find the shortest route through a server room grid as
// more maintenance obstacles appear, then report the first obstacle that blocks
// the exit completely.

const MaxGridSize = 32
const MaxGridCells = MaxGridSize * MaxGridSize

struct ByteDrop
{
    x: u32
    y: u32
}

struct RouteReport
{
    shortestSteps:         u32
    firstBlockingX:        u32
    firstBlockingY:        u32
    firstBlockingDropCount:u32
}

func cellIndex(x, y, gridSize: u32)->u32
{
    return y * gridSize + x
}

func hasEscapeRoute(outSteps: *u32, drops: const [..] ByteDrop, gridSize, dropCount: u32)->bool
{
    let totalCells = gridSize * gridSize
    @assert(gridSize <= MaxGridSize)
    @assert(totalCells <= MaxGridCells)
    @assert(dropCount <= cast(u32) @countof(drops))

    var blocked: [MaxGridCells] bool

    for dropCount
    {
        let drop = drops[@index]
        @assert(drop.x < gridSize)
        @assert(drop.y < gridSize)
        blocked[cellIndex(drop.x, drop.y, gridSize)] = true
    }

    let startCell = cellIndex(0, 0, gridSize)
    let endCell = cellIndex(gridSize - 1, gridSize - 1, gridSize)
    if blocked[startCell] or blocked[endCell] do
        return false

    var visited: [MaxGridCells] bool
    var distance: [MaxGridCells] u32
    var queue: [MaxGridCells] u32
    var head: u32
    var tail: u32

    visited[startCell] = true
    queue[tail] = startCell
    tail += 1

    while head < tail
    {
        let current = queue[head]
        head += 1

        if current == endCell
        {
            dref outSteps = distance[current]
            return true
        }

        let x = current % gridSize
        let y = current / gridSize
        let nextDistance = distance[current] + 1

        if x > 0
        {
            let nextCell = cellIndex(x - 1, y, gridSize)
            if !blocked[nextCell] and !visited[nextCell]
            {
                visited[nextCell] = true
                distance[nextCell] = nextDistance
                queue[tail] = nextCell
                tail += 1
            }
        }

        if x + 1 < gridSize
        {
            let nextCell = cellIndex(x + 1, y, gridSize)
            if !blocked[nextCell] and !visited[nextCell]
            {
                visited[nextCell] = true
                distance[nextCell] = nextDistance
                queue[tail] = nextCell
                tail += 1
            }
        }

        if y > 0
        {
            let nextCell = cellIndex(x, y - 1, gridSize)
            if !blocked[nextCell] and !visited[nextCell]
            {
                visited[nextCell] = true
                distance[nextCell] = nextDistance
                queue[tail] = nextCell
                tail += 1
            }
        }

        if y + 1 < gridSize
        {
            let nextCell = cellIndex(x, y + 1, gridSize)
            if !blocked[nextCell] and !visited[nextCell]
            {
                visited[nextCell] = true
                distance[nextCell] = nextDistance
                queue[tail] = nextCell
                tail += 1
            }
        }
    }

    return false
}

func analyzeObstacleDrops(drops: const [..] ByteDrop, gridSize, initialDropCount: u32)->RouteReport
{
    var result: RouteReport
    var steps: u32

    @assert(hasEscapeRoute(&steps, drops, gridSize, initialDropCount))
    result.shortestSteps = steps

    let extraDrops = cast(u32) @countof(drops) - initialDropCount
    for extraDrops
    {
        let dropCount = initialDropCount + cast(u32) @index + 1
        if !hasEscapeRoute(&steps, drops, gridSize, dropCount)
        {
            let blocking = drops[dropCount - 1]
            result.firstBlockingX = blocking.x
            result.firstBlockingY = blocking.y
            result.firstBlockingDropCount = dropCount
            break
        }
    }

    @assert(result.firstBlockingDropCount != 0)
    return result
}

#test
{
    const sampleDrops: [25] ByteDrop =
    [
        {5, 4},
        {4, 2},
        {4, 5},
        {3, 0},
        {2, 1},
        {6, 3},
        {2, 4},
        {1, 5},
        {0, 6},
        {3, 3},
        {2, 6},
        {5, 1},
        {1, 2},
        {5, 5},
        {2, 5},
        {6, 5},
        {1, 4},
        {0, 4},
        {6, 4},
        {1, 1},
        {6, 1},
        {1, 0},
        {0, 5},
        {1, 6},
        {2, 0},
    ]

    let sampleReport = analyzeObstacleDrops(sampleDrops, 7, 12)

    @assert(sampleReport.shortestSteps == 22)
    @assert(sampleReport.firstBlockingX == 6)
    @assert(sampleReport.firstBlockingY == 1)
    @assert(sampleReport.firstBlockingDropCount == 21)

    const compactDrops: [7] ByteDrop =
    [
        {1, 0},
        {1, 1},
        {1, 2},
        {3, 2},
        {2, 3},
        {1, 3},
        {0, 3},
    ]

    let compactReport = analyzeObstacleDrops(compactDrops, 5, 4)

    @assert(compactReport.shortestSteps == 8)
    @assert(compactReport.firstBlockingX == 0)
    @assert(compactReport.firstBlockingY == 3)
    @assert(compactReport.firstBlockingDropCount == 7)
}
