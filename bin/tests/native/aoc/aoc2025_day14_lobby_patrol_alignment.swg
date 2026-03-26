#global fileprivate

// Real-life example: track lobby patrol robots on a wrapping floor plan,
// compute the quadrant safety factor after a fixed interval, and locate the
// earliest moment when the formation is most compact.

struct PatrolRobot
{
    startX: s32
    startY: s32
    speedX: s32
    speedY: s32
}

struct PatrolReport
{
    safetyFactor:    u64
    mostCompactStep: u32
    compactArea:     u32
}

func wrapCoordinate(value, size: s32)->s32
{
    var result = value % size
    if result < 0 do
        result += size
    return result
}

func robotX(robot: PatrolRobot, step, width: s32)->s32
{
    return wrapCoordinate(robot.startX + robot.speedX * step, width)
}

func robotY(robot: PatrolRobot, step, height: s32)->s32
{
    return wrapCoordinate(robot.startY + robot.speedY * step, height)
}

func computeSafetyFactor(robots: const [..] PatrolRobot, width, height, step: s32)->u64
{
    let middleX = width / 2
    let middleY = height / 2

    var topLeft: u64
    var topRight: u64
    var bottomLeft: u64
    var bottomRight: u64

    foreach robot in robots
    {
        let x = robotX(robot, step, width)
        let y = robotY(robot, step, height)

        if x == middleX or y == middleY do
            continue

        if x < middleX and y < middleY
        {
            topLeft += 1
        }
        else
        {
            if x > middleX and y < middleY
            {
                topRight += 1
            }

            if x < middleX and y > middleY
            {
                bottomLeft += 1
            }

            if x > middleX and y > middleY
            {
                bottomRight += 1
            }
        }
    }

    return topLeft * topRight * bottomLeft * bottomRight
}

func analyzePatrol(robots: const [..] PatrolRobot, width, height, safetyStep, searchLimit: s32)->PatrolReport
{
    var result: PatrolReport
    result.safetyFactor = computeSafetyFactor(robots, width, height, safetyStep)
    result.compactArea = Swag.U32.Max

    for cast(u32) (searchLimit + 1)
    {
        let step = cast(s32) @index

        var minX = Swag.S32.Max
        var minY = Swag.S32.Max
        var maxX = Swag.S32.Min
        var maxY = Swag.S32.Min

        foreach robot in robots
        {
            let x = robotX(robot, step, width)
            let y = robotY(robot, step, height)

            if x < minX do
                minX = x
            if y < minY do
                minY = y
            if x > maxX do
                maxX = x
            if y > maxY do
                maxY = y
        }

        let area = cast(u32) (maxX - minX + 1) * cast(u32) (maxY - minY + 1)
        if area < result.compactArea
        {
            result.compactArea = area
            result.mostCompactStep = cast(u32) step
        }
    }

    return result
}

#test
{
    const sampleRobots: [6] PatrolRobot =
    [
        {startX: 0, startY: 0, speedX: 1, speedY: 1},
        {startX: 10, startY: 0, speedX: -1, speedY: 1},
        {startX: 0, startY: 6, speedX: 1, speedY: -1},
        {startX: 10, startY: 6, speedX: -1, speedY: -1},
        {startX: 3, startY: 1, speedX: 0, speedY: 1},
        {startX: 7, startY: 5, speedX: 0, speedY: -1},
    ]

    let sampleReport = analyzePatrol(sampleRobots, 11, 7, 2, 20)

    @assert(sampleReport.safetyFactor == 1'u64)
    @assert(sampleReport.mostCompactStep == 3'u32)
    @assert(sampleReport.compactArea == 15'u32)

    const concourseRobots: [8] PatrolRobot =
    [
        {startX: 1, startY: 0, speedX: 0, speedY: 1},
        {startX: 2, startY: 6, speedX: 0, speedY: -1},
        {startX: 8, startY: 0, speedX: 0, speedY: 1},
        {startX: 9, startY: 6, speedX: 0, speedY: -1},
        {startX: 0, startY: 3, speedX: 1, speedY: 0},
        {startX: 10, startY: 3, speedX: -1, speedY: 0},
        {startX: 5, startY: 1, speedX: 0, speedY: 1},
        {startX: 5, startY: 5, speedX: 0, speedY: -1},
    ]

    let concourseReport = analyzePatrol(concourseRobots, 11, 7, 1, 20)

    @assert(concourseReport.safetyFactor == 1'u64)
    @assert(concourseReport.mostCompactStep == 2'u32)
    @assert(concourseReport.compactArea == 27'u32)
}
