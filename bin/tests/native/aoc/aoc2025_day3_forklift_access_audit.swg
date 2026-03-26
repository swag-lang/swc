#global fileprivate

// Real-life example: audit which paper rolls in a warehouse print area can be
// picked by a forklift without squeezing into dense clusters.

struct ForkliftAudit
{
    rowCount:         u32
    columnCount:      u32
    totalRolls:       u32
    accessibleRolls:  u32
    blockedRolls:     u32
    densestCluster:   u32
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
            if rowOffset == 0 and columnOffset == 0 do
                continue

            let neighborRow = cast(s32) row + rowOffset
            let neighborColumn = cast(s32) column + columnOffset

            if neighborRow < 0 or neighborColumn < 0 do
                continue

            if neighborRow >= cast(s32) @countof(plan) do
                continue

            let line = cast(const [..] u8) plan[cast(u32) neighborRow]
            if neighborColumn >= cast(s32) @countof(line) do
                continue

            neighbors += line[cast(u32) neighborColumn] == 64'u8 ? 1'u32 : 0'u32
        }
    }

    return neighbors
}

func auditForkliftAccess(plan: const [..] string)->ForkliftAudit
{
    @assert(@countof(plan) > 0)

    var result: ForkliftAudit
    result.rowCount = cast(u32) @countof(plan)
    result.columnCount = cast(u32) @countof(cast(const [..] u8) plan[0])

    foreach line, row in plan
    {
        let bytes = cast(const [..] u8) line
        @assert(@countof(bytes) == result.columnCount)

        for column in @countof(bytes)
        {
            var neighbors: u32

            if bytes[column] == 64'u8 do
                neighbors = countAdjacentRolls(plan, cast(u32) row, cast(u32) column)
            if bytes[column] == 64'u8 do
                result.totalRolls += 1
            if bytes[column] == 64'u8 do
                result.densestCluster = maxU32(result.densestCluster, neighbors)
            if bytes[column] == 64'u8 and neighbors < 4 do
                result.accessibleRolls += 1
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
        "@.@.@@@.@.",
    ]

    let sampleAudit = auditForkliftAccess(samplePlan)

    @assert(sampleAudit.rowCount == 10'u32)
    @assert(sampleAudit.columnCount == 10'u32)
    @assert(sampleAudit.totalRolls == 71'u32)
    @assert(sampleAudit.accessibleRolls == 13'u32)
    @assert(sampleAudit.blockedRolls == 58'u32)
    @assert(sampleAudit.densestCluster == 8'u32)
    @assert(countAdjacentRolls(samplePlan, 0, 2) == 3'u32)
    @assert(countAdjacentRolls(samplePlan, 5, 4) == 7'u32)

    const loadingBayPlan: [6] string =
    [
        "..@...",
        ".@@@..",
        "@@.@@.",
        ".@@@@.",
        "..@@..",
        "...@..",
    ]

    let loadingBayAudit = auditForkliftAccess(loadingBayPlan)

    @assert(loadingBayAudit.rowCount == 6'u32)
    @assert(loadingBayAudit.columnCount == 6'u32)
    @assert(loadingBayAudit.totalRolls == 15'u32)
    @assert(loadingBayAudit.accessibleRolls == 3'u32)
    @assert(loadingBayAudit.blockedRolls == 12'u32)
    @assert(loadingBayAudit.densestCluster == 6'u32)
    @assert(countAdjacentRolls(loadingBayPlan, 0, 2) == 3'u32)
    @assert(countAdjacentRolls(loadingBayPlan, 3, 3) == 6'u32)
}
