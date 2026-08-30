#global private

// Real-life example: simulate a vertical optical splitter rack and count how
// many times an incoming beam is divided while moving through the manifold.

struct SplitterAudit
{
    rowCount:           u32
    columnCount:        u32
    splitCount:         u32
    survivingBeamCount: u32
}

func countActive(flags: const [..] bool)->u32
{
    var result: u32

    for flag in flags
    {
        if flag do
            result += 1
    }

    return result
}

func findStartColumn(plan: const [..] string)->u32
{
    let firstRow = cast(const [..] u8) plan[0]

    for column in firstRow.count
    {
        if firstRow[column] == 'S' do
            return cast(u32) column
    }

    Swag.assert(false)
    return 0
}

func auditSplitterRack(plan: const [..] string)->SplitterAudit
{
    Swag.assert(plan.count > 0)

    let firstRow = cast(const [..] u8) plan[0]
    let width    = cast(u32) firstRow.count

    Swag.assert(width <= 96)

    for line in plan
    {
        Swag.assert((cast(const [..] u8) line).count == width)
    }

    var current: [96] bool
    var next:    [96] bool
    var result:  SplitterAudit

    result.rowCount                = cast(u32) plan.count
    result.columnCount             = width
    current[findStartColumn(plan)] = true

    for row in 1 to plan.count - 1
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
        "..............."
        ]

    let sampleAudit = auditSplitterRack(samplePlan)

    Swag.assert(sampleAudit.rowCount == 16'u32)
    Swag.assert(sampleAudit.columnCount == 15'u32)
    Swag.assert(sampleAudit.splitCount == 21'u32)
    Swag.assert(sampleAudit.survivingBeamCount == 9'u32)

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
        ".^.^.^.^."
        ]

    let serviceAudit = auditSplitterRack(servicePlan)

    Swag.assert(serviceAudit.rowCount == 9'u32)
    Swag.assert(serviceAudit.columnCount == 9'u32)
    Swag.assert(serviceAudit.splitCount == 9'u32)
    Swag.assert(serviceAudit.survivingBeamCount == 5'u32)
}
