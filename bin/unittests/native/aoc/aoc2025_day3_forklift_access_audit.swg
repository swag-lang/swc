#global private

// Real-life example: audit which paper rolls in a warehouse print area can be
// picked by a forklift without squeezing into dense clusters.

struct ForkliftAudit
{
    rowCount:        u32
    columnCount:     u32
    totalRolls:      u32
    accessibleRolls: u32
    blockedRolls:    u32
    densestCluster:  u32
}

func maxU32(lhs, rhs: u32)->u32
{
    return lhs > rhs ? lhs : rhs
}

func countAdjacentRolls(plan: const [..] string, row, column: u32)->u32
{
    var neighbors: u32

    for rowOffset in -1 to 1
    {
        for columnOffset in -1 to 1
        {
            if rowOffset == 0 and columnOffset == 0
            {
                continue
            }

            let neighborRow    = cast(s32, row) + rowOffset
            let neighborColumn = cast(s32, column) + columnOffset

            if neighborRow < 0 or neighborColumn < 0
            {
                continue
            }

            if neighborRow >= cast(s32, plan.count)
            {
                continue
            }

            let line = cast(const [..] u8, plan[cast(u32, neighborRow)])
            if neighborColumn >= cast(s32, line.count)
            {
                continue
            }

            neighbors += line[cast(u32, neighborColumn)] == 64_u8 ? 1_u32 : 0_u32
        }
    }

    return neighbors
}

func auditForkliftAccess(plan: const [..] string)->ForkliftAudit
{
    Swag.assert(plan.count > 0)

    var result: ForkliftAudit
    result.rowCount    = cast(u32, plan.count)
    result.columnCount = cast(u32, cast(const [..] u8, plan[0]).count)

    for line, row in plan
    {
        let bytes = cast(const [..] u8, line)
        Swag.assert(bytes.count == result.columnCount)

        for column in bytes.count
        {
            var neighbors: u32

            if bytes[column] == 64_u8
            {
                neighbors = countAdjacentRolls(plan, cast(u32, row), cast(u32, column))
            }
            if bytes[column] == 64_u8
            {
                result.totalRolls += 1
            }
            if bytes[column] == 64_u8
            {
                result.densestCluster = maxU32(result.densestCluster, neighbors)
            }
            if bytes[column] == 64_u8 and neighbors < 4
            {
                result.accessibleRolls += 1
            }
        }
    }

    result.blockedRolls = result.totalRolls - result.accessibleRolls
    return result
}

#test
{
    const samplePlan: [10] string =
        [
        "..@@.@@@@.",
        "@@@.@.@.@@",
        "@@@@@.@.@@",
        "@.@@@@..@.",
        "@@.@@@@.@@",
        ".@@@@@@@.@",
        ".@.@.@.@@@",
        "@.@@@.@@@@",
        ".@@@@@@@@.",
        "@.@.@@@.@."
        ]

    let sampleAudit = auditForkliftAccess(samplePlan)

    Swag.require(sampleAudit.rowCount == 10_u32)
    Swag.require(sampleAudit.columnCount == 10_u32)
    Swag.require(sampleAudit.totalRolls == 71_u32)
    Swag.require(sampleAudit.accessibleRolls == 13_u32)
    Swag.require(sampleAudit.blockedRolls == 58_u32)
    Swag.require(sampleAudit.densestCluster == 8_u32)
    Swag.require(countAdjacentRolls(samplePlan, 0, 2) == 3_u32)
    Swag.require(countAdjacentRolls(samplePlan, 5, 4) == 7_u32)

    const loadingBayPlan: [6] string =
        [
        "..@...",
        ".@@@..",
        "@@.@@.",
        ".@@@@.",
        "..@@..",
        "...@.."
        ]

    let loadingBayAudit = auditForkliftAccess(loadingBayPlan)

    Swag.require(loadingBayAudit.rowCount == 6_u32)
    Swag.require(loadingBayAudit.columnCount == 6_u32)
    Swag.require(loadingBayAudit.totalRolls == 15_u32)
    Swag.require(loadingBayAudit.accessibleRolls == 3_u32)
    Swag.require(loadingBayAudit.blockedRolls == 12_u32)
    Swag.require(loadingBayAudit.densestCluster == 6_u32)
    Swag.require(countAdjacentRolls(loadingBayPlan, 0, 2) == 3_u32)
    Swag.require(countAdjacentRolls(loadingBayPlan, 3, 3) == 6_u32)
}
