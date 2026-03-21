#global fileprivate

// Real-life example: route a cart through a hallway network where moving
// forward is cheap but every turn is expensive.

const MaxHallwayCells = 256
const MaxHallwayStates = MaxHallwayCells * 4

struct RouteReport
{
    bestScore: u64
    stepCount: u32
}

func lineWidth(line: string)->u32
{
    return cast(u32) @countof(cast(const [..] u8) line)
}

func cellIndex(x, y, width: u32)->u32
{
    return y * width + x
}

func stateIndex(cell, direction: u32)->u32
{
    return cell * 4'u32 + direction
}

func forwardX(x: s32, direction: u32)->s32
{
    switch direction
    {
        case 0:
            return x + 1
        case 2:
            return x - 1
        default:
            return x
    }
}

func forwardY(y: s32, direction: u32)->s32
{
    switch direction
    {
        case 1:
            return y + 1
        case 3:
            return y - 1
        default:
            return y
    }
}

func analyzeRoute(layout: const [..] string)->RouteReport
{
    let height = cast(u32) @countof(layout)
    let width = lineWidth(layout[0])
    let totalCells = width * height

    @assert(totalCells <= MaxHallwayCells)

    var cells: [MaxHallwayCells] u8
    var startCell: u32
    var endCell: u32

    foreach _, rowIndex in layout
    {
        @assert(lineWidth(layout[rowIndex]) == width)
        let row = cast(const [..] u8) layout[rowIndex]

        for width
        {
            let x = cast(u32) @index
            let index = cellIndex(x, cast(u32) rowIndex, width)
            let value = row[x]

            cells[index] = value
            if value == 'S''u8 do
                startCell = index
            if value == 'E''u8 do
                endCell = index
        }
    }

    var dist: [MaxHallwayStates] u64
    var steps: [MaxHallwayStates] u32
    var visited: [MaxHallwayStates] bool

    for MaxHallwayStates
    {
        dist[@index] = Swag.U64.Max
        steps[@index] = Swag.U32.Max
    }

    let startState = stateIndex(startCell, 0)
    dist[startState] = 0'u64
    steps[startState] = 0'u32

    let stateCount = totalCells * 4'u32

    for stateCount
    {
        var bestState = Swag.U32.Max
        var bestDistance = Swag.U64.Max
        var bestStepCount = Swag.U32.Max

        for stateCount
        {
            let candidate = cast(u32) @index
            if visited[candidate] do
                continue

            let candidateDistance = dist[candidate]
            if candidateDistance < bestDistance or candidateDistance == bestDistance and steps[candidate] < bestStepCount
            {
                bestState = candidate
                bestDistance = candidateDistance
                bestStepCount = steps[candidate]
            }
        }

        if bestState == Swag.U32.Max or bestDistance == Swag.U64.Max do
            break

        visited[bestState] = true

        let cell = bestState / 4'u32
        let direction = bestState % 4'u32
        let x = cast(s32) (cell % width)
        let y = cast(s32) (cell / width)

        let nextX = forwardX(x, direction)
        let nextY = forwardY(y, direction)
        let nextCell = cellIndex(cast(u32) nextX, cast(u32) nextY, width)
        if cells[nextCell] != '#''u8
        {
            let forwardState = stateIndex(nextCell, direction)
            let candidateDistance = bestDistance + 1'u64
            let candidateSteps = bestStepCount + 1'u32

            if candidateDistance < dist[forwardState] or candidateDistance == dist[forwardState] and candidateSteps < steps[forwardState]
            {
                dist[forwardState] = candidateDistance
                steps[forwardState] = candidateSteps
            }
        }

        let rightDirection = (direction + 1'u32) % 4'u32
        let leftDirection = (direction + 3'u32) % 4'u32

        let rightState = stateIndex(cell, rightDirection)
        if bestDistance + 1000'u64 < dist[rightState] or bestDistance + 1000'u64 == dist[rightState] and bestStepCount < steps[rightState]
        {
            dist[rightState] = bestDistance + 1000'u64
            steps[rightState] = bestStepCount
        }

        let leftState = stateIndex(cell, leftDirection)
        if bestDistance + 1000'u64 < dist[leftState] or bestDistance + 1000'u64 == dist[leftState] and bestStepCount < steps[leftState]
        {
            dist[leftState] = bestDistance + 1000'u64
            steps[leftState] = bestStepCount
        }
    }

    var result: RouteReport
    result.bestScore = Swag.U64.Max
    result.stepCount = Swag.U32.Max

    for 4
    {
        let endState = stateIndex(endCell, cast(u32) @index)
        if dist[endState] < result.bestScore or dist[endState] == result.bestScore and steps[endState] < result.stepCount
        {
            result.bestScore = dist[endState]
            result.stepCount = steps[endState]
        }
    }

    return result
}

#test
{
    const sampleHall: [5] string =
    [
        "#######",
        "#....E#",
        "#.#.#.#",
        "#S....#",
        "#######",
    ]

    let sampleRoute = analyzeRoute(sampleHall)

    @assert(sampleRoute.bestScore == 1006'u64)
    @assert(sampleRoute.stepCount == 6'u32)

    const serviceHall: [5] string =
    [
        "#########",
        "#S#....E#",
        "#.#.###.#",
        "#...#...#",
        "#########",
    ]

    let serviceRoute = analyzeRoute(serviceHall)

    @assert(serviceRoute.bestScore == 4010'u64)
    @assert(serviceRoute.stepCount == 10'u32)
}
