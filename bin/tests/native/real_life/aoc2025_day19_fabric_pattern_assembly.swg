#global fileprivate

// Real-life example: count how many requested fabric badges can be assembled
// from a fixed set of stripe patterns and sum all possible assemblies.

const MaxDesignLength = 64

struct DesignReport
{
    matchableCount:    u32
    totalArrangements: u64
}

func matchesPattern(design: const [..] u8, startIndex: u32, pattern: string)->bool
{
    let patternBytes = cast(const [..] u8) pattern
    let patternLength = cast(u32) @countof(patternBytes)

    if startIndex + patternLength > cast(u32) @countof(design) do
        return false

    for patternLength
    {
        let offset = cast(u32) @index
        if design[startIndex + offset] != patternBytes[offset] do
            return false
    }

    return true
}

func countAssemblies(patterns: const [..] string, design: string)->u64
{
    let designBytes = cast(const [..] u8) design
    let designLength = cast(u32) @countof(designBytes)
    @assert(designLength <= MaxDesignLength)

    var ways: [MaxDesignLength + 1] u64
    ways[0] = 1

    for designLength
    {
        let index = cast(u32) @index
        if ways[index] == 0 do
            continue

        foreach pattern in patterns
        {
            if matchesPattern(designBytes, index, pattern)
            {
                let patternLength = cast(u32) @countof(cast(const [..] u8) pattern)
                ways[index + patternLength] += ways[index]
            }
        }
    }

    return ways[designLength]
}

func analyzeBadgeRequests(patterns: const [..] string, designs: const [..] string)->DesignReport
{
    var result: DesignReport

    foreach design in designs
    {
        let arrangements = countAssemblies(patterns, design)
        if arrangements != 0
        {
            result.matchableCount += 1
            result.totalArrangements += arrangements
        }
    }

    return result
}

#test
{
    const samplePatterns: [8] string = ["r", "wr", "b", "g", "bwu", "rb", "gb", "br"]
    const sampleDesigns: [8] string =
    [
        "brwrr",
        "bggr",
        "gbbr",
        "rrbgbr",
        "ubwu",
        "bwurrg",
        "brgr",
        "bbrgwb",
    ]

    let sampleReport = analyzeBadgeRequests(samplePatterns, sampleDesigns)

    @assert(sampleReport.matchableCount == 6)
    @assert(sampleReport.totalArrangements == 16)

    const compactPatterns: [4] string = ["a", "ab", "ba", "b"]
    const compactDesigns: [4] string = ["aba", "abba", "bbb", "c"]

    let compactReport = analyzeBadgeRequests(compactPatterns, compactDesigns)

    @assert(compactReport.matchableCount == 3)
    @assert(compactReport.totalArrangements == 8)
}
