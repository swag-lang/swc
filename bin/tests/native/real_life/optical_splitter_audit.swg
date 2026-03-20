#global fileprivate

// Real-life example: simulate a vertical optical splitter rack and count how
// many times an incoming beam is divided while moving through the manifold.

struct SplitterAudit
{
    rowCount:      u32
    columnCount:   u32
    splitCount:    u32
    survivingBeamCount: u32
}

func countActive(flags: const [..] bool)->u32
{
    var result: u32

    foreach flag in flags
    {
        if flag do
            result += 1
    }

    return result
}

func findStartColumn(plan: const [..] string)->u32
{
    let firstRow = cast(const [..] u8) plan[0]

    for column in @countof(firstRow)
    {
        if firstRow[column] == 'S' do
            return cast(u32) column
    }

    @assert(false)
    return 0
}

func auditSplitterRack(plan: const [..] string)->SplitterAudit
{
    @assert(@countof(plan) > 0)

    let firstRow = cast(const [..] u8) plan[0]
    let width = cast(u32) @countof(firstRow)

    @assert(width <= 96)

    foreach line in plan
    {
        @assert(@countof(cast(const [..] u8) line) == width)
    }

    var current: [96] bool
    var next: [96] bool
    var result: SplitterAudit

    result.rowCount = cast(u32) @countof(plan)
    result.columnCount = width
    current[findStartColumn(plan)] = true

    for row in 1 to @countof(plan) - 1
    {
        let bytes = cast(const [..] u8) plan[row]

        for column in width
        {
            next[column] = false
        }

        for column in width
        {

            if current[column] == false do
                continue

            if bytes[column] == '^'
            {
                result.splitCount += 1

                if column > 0 do
                    next[column - 1] = true
                if column + 1 < width do
                    next[column + 1] = true
            }
            else
            {
                next[column] = true
            }
        }

        for column in width
        {
            current[column] = next[column]
        }
    }

    result.survivingBeamCount = countActive(current[0 to width])
    return result
}

#test
{
    const samplePlan: [16] string =
    [
        ".......S.......",
        "...............",
        ".......^.......",
        "...............",
        "......^.^......",
        "...............",
        ".....^.^.^.....",
        "...............",
        "....^.^...^....",
        "...............",
        "...^.^...^.^...",
        "...............",
        "..^...^.....^..",
        "...............",
        ".^.^.^.^.^...^.",
        "...............",
    ]

    let sampleAudit = auditSplitterRack(samplePlan)

    @assert(sampleAudit.rowCount == 16'u32)
    @assert(sampleAudit.columnCount == 15'u32)
    @assert(sampleAudit.splitCount == 21'u32)
    @assert(sampleAudit.survivingBeamCount == 9'u32)

    const servicePlan: [9] string =
    [
        "....S....",
        ".........",
        "....^....",
        ".........",
        "...^.^...",
        ".........",
        "..^...^..",
        ".........",
        ".^.^.^.^.",
    ]

    let serviceAudit = auditSplitterRack(servicePlan)

    @assert(serviceAudit.rowCount == 9'u32)
    @assert(serviceAudit.columnCount == 9'u32)
    @assert(serviceAudit.splitCount == 9'u32)
    @assert(serviceAudit.survivingBeamCount == 5'u32)
}
