#global fileprivate

// Real-life example: compute the cheapest token spend for prize-booth machines
// whose two button vectors must land exactly on a target position.

struct PrizeMachine
{
    buttonAX:  s64
    buttonAY:  s64
    buttonBX:  s64
    buttonBY:  s64
    prizeX:    s64
    prizeY:    s64
}

struct PrizeReport
{
    solvableCount:  u32
    totalTokenCost: s64
}

func solveMachine(machine: PrizeMachine, prizeOffset: s64)->s64
{
    let targetX = machine.prizeX + prizeOffset
    let targetY = machine.prizeY + prizeOffset
    let determinant = machine.buttonAX * machine.buttonBY - machine.buttonAY * machine.buttonBX

    if determinant == 0 do
        return 0

    let aNumerator = targetX * machine.buttonBY - targetY * machine.buttonBX
    let bNumerator = machine.buttonAX * targetY - machine.buttonAY * targetX

    if aNumerator % determinant != 0 or bNumerator % determinant != 0 do
        return 0

    let pressA = aNumerator / determinant
    let pressB = bNumerator / determinant

    if pressA < 0 or pressB < 0 do
        return 0

    return pressA * 3 + pressB
}

func analyzeMachines(machines: const [..] PrizeMachine, prizeOffset: s64)->PrizeReport
{
    var result: PrizeReport

    foreach machine in machines
    {
        let tokenCost = solveMachine(machine, prizeOffset)
        if tokenCost > 0
        {
            result.solvableCount += 1
            result.totalTokenCost += tokenCost
        }
    }

    return result
}

#test
{
    const sampleMachines: [4] PrizeMachine =
    [
        {buttonAX: 94, buttonAY: 34, buttonBX: 22, buttonBY: 67, prizeX: 8400, prizeY: 5400},
        {buttonAX: 26, buttonAY: 66, buttonBX: 67, buttonBY: 21, prizeX: 12748, prizeY: 12176},
        {buttonAX: 17, buttonAY: 86, buttonBX: 84, buttonBY: 37, prizeX: 7870, prizeY: 6450},
        {buttonAX: 69, buttonAY: 23, buttonBX: 27, buttonBY: 71, prizeX: 18641, prizeY: 10279},
    ]

    let sampleReport = analyzeMachines(sampleMachines, 0)
    let calibratedReport = analyzeMachines(sampleMachines, 10_000_000_000_000)

    @assert(sampleReport.solvableCount == 2'u32)
    @assert(sampleReport.totalTokenCost == 480)
    @assert(calibratedReport.solvableCount == 2'u32)
    @assert(calibratedReport.totalTokenCost == 875_318_608_908)

    const arcadeMachines: [3] PrizeMachine =
    [
        {buttonAX: 4, buttonAY: 2, buttonBX: 1, buttonBY: 3, prizeX: 9, prizeY: 7},
        {buttonAX: 6, buttonAY: 1, buttonBX: 2, buttonBY: 3, prizeX: 22, prizeY: 11},
        {buttonAX: 5, buttonAY: 4, buttonBX: 2, buttonBY: 1, prizeX: 18, prizeY: 11},
    ]

    let arcadeReport = analyzeMachines(arcadeMachines, 0)
    let recalibratedArcade = analyzeMachines(arcadeMachines, 100)

    @assert(arcadeReport.solvableCount == 1'u32)
    @assert(arcadeReport.totalTokenCost == 7)
    @assert(recalibratedArcade.solvableCount == 2'u32)
    @assert(recalibratedArcade.totalTokenCost == 148)
}
