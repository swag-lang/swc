#global fileprivate

// Real-life example: audit a cafeteria inventory sheet to determine how many
// available ingredient IDs are still fresh.

struct IdRange
{
    min: u32
    max: u32
}

struct FreshIdAudit
{
    rangeCount:        u32
    availableCount:    u32
    freshCount:        u32
    spoiledCount:      u32
    overlappingFresh:  u32
}

func parseNumber(bytes: const [..] u8, index: *u32)->u32
{
    var result: u32

    while dref index < @countof(bytes) and bytes[dref index] >= '0' and bytes[dref index] <= '9'
    {
        result = result * 10'u32 + cast(u32) (bytes[dref index] - '0')
        dref index += 1
    }

    return result
}

func parseRange(text: string)->IdRange
{
    let bytes = cast(const [..] u8) text

    var result: IdRange
    var index: u32

    result.min = parseNumber(bytes, &index)
    index += 1
    result.max = parseNumber(bytes, &index)
    return result
}

func countRangeMatches(ranges: const [..] IdRange, value: u32)->u32
{
    var result: u32

    foreach range in ranges
    {
        if value >= range.min and value <= range.max do
            result += 1
    }

    return result
}

func auditFreshIds(rangeLines: const [..] string, availableIds: const [..] u32)->FreshIdAudit
{
    var ranges: [16] IdRange
    var result: FreshIdAudit

    foreach line in rangeLines
    {
        @assert(result.rangeCount < 16)
        ranges[result.rangeCount] = parseRange(line)
        result.rangeCount += 1
    }

    foreach value in availableIds
    {
        let matchCount = countRangeMatches(ranges[0 to result.rangeCount], value)
        result.availableCount += 1

        if matchCount == 0 do
            result.spoiledCount += 1
        else
        {
            result.freshCount += 1
            if matchCount > 1 do
                result.overlappingFresh += 1
        }
    }

    return result
}

#test
{
    const sampleRanges: [4] string = ["3-5", "10-14", "16-20", "12-18"]
    const sampleAvailable: [6] u32 = [1, 5, 8, 11, 17, 32]

    let sampleAudit = auditFreshIds(sampleRanges, sampleAvailable)

    @assert(sampleAudit.rangeCount == 4'u32)
    @assert(sampleAudit.availableCount == 6'u32)
    @assert(sampleAudit.freshCount == 3'u32)
    @assert(sampleAudit.spoiledCount == 3'u32)
    @assert(sampleAudit.overlappingFresh == 1'u32)

    const pantryRanges: [4] string = ["20-25", "30-32", "32-35", "100-110"]
    const pantryAvailable: [7] u32 = [19, 20, 24, 32, 34, 105, 999]

    let pantryAudit = auditFreshIds(pantryRanges, pantryAvailable)

    @assert(pantryAudit.rangeCount == 4'u32)
    @assert(pantryAudit.availableCount == 7'u32)
    @assert(pantryAudit.freshCount == 5'u32)
    @assert(pantryAudit.spoiledCount == 2'u32)
    @assert(pantryAudit.overlappingFresh == 1'u32)
}
