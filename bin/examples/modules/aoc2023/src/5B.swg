/*
--- Part Two ---
Everyone will starve if you only plant such a small number of seeds. Re-reading the almanac, it looks like the seeds: line actually describes ranges of seed numbers.

The values on the initial seeds: line come in pairs. Within each pair, the first value is the start of the range and the second value is the length of the range. So, in the first line of the example above:

seeds: 79 14 55 13
This line describes two ranges of seed numbers to be planted in the garden. The first range starts with seed number 79 and contains 14 values: 79, 80, ..., 91, 92. The second range starts with seed number 55 and contains 13 values: 55, 56, ..., 66, 67.

Now, rather than considering four seed numbers, you need to consider a total of 27 seed numbers.

In the above example, the lowest location number can be obtained from seed number 82, which corresponds to soil 84, fertilizer 84, water 84, light 77, temperature 45, humidity 46, and location 46. So, the lowest location number is 46.

Consider all of the initial seed numbers listed in the ranges on the first line of the almanac. What is the lowest location number that corresponds to any of the initial seed numbers?
*/

using Core

private enum Mode
{
    ToSoil
    ToFertilizer
    ToWater
    ToLight
    ToTemperature
    ToHumidity
    ToLocation
    Invalid
}

private struct Range
{
    sourceStart, sourceEnd: u64
    destinationStart:       u64
}

private struct SeedRange
{
    start, end: u64
}

private var seeds:   Array'u64
private var convert: [7] Array'Range

func day5B()
{
    let dataPath = Path.combine(Path.directoryName(#curlocation.fileName), "5.txt")
    let lines    = expect File.readAllLines(dataPath)

    var mode = Mode.Invalid
    for l in lines
    {
        if l.isEmpty() do
            continue

        var isHeader = false
        switch l.toString()
        {
        case "seed-to-soil map:":
            mode     = .ToSoil
            isHeader = true

        case "soil-to-fertilizer map:":
            mode     = .ToFertilizer
            isHeader = true

        case "fertilizer-to-water map:":
            mode     = .ToWater
            isHeader = true

        case "water-to-light map:":
            mode     = .ToLight
            isHeader = true

        case "light-to-temperature map:":
            mode     = .ToTemperature
            isHeader = true

        case "temperature-to-humidity map:":
            mode     = .ToHumidity
            isHeader = true

        case "humidity-to-location map:":
            mode     = .ToLocation
            isHeader = true
        }

        if isHeader do
            continue

        if mode == .Invalid
        {
            let seedField  = Tokenize.split(l[], ':'u8)
            let seedTokens = Tokenize.split(seedField[1], ' 'u8)
            for seed in seedTokens do
                seeds.add(expect StrConv.toU64(seed))
            continue
        }

        let mappingValues = Tokenize.split(l[], ' 'u8)
        var mapping: Range
        let sourceLength  = expect StrConv.toU64(mappingValues[2])
        mapping.destinationStart = expect StrConv.toU64(mappingValues[0])
        mapping.sourceStart      = expect StrConv.toU64(mappingValues[1])
        mapping.sourceEnd        = mapping.sourceStart + sourceLength - 1
        convert[cast(s32, mode)].add(mapping)
    }

    var ranges: Array'SeedRange
    for pairIndex in seeds.count / 2
    {
        let seedIndex  = pairIndex * 2
        let rangeStart = seeds[seedIndex]
        let rangeEnd   = rangeStart + seeds[seedIndex + 1] - 1
        ranges.add({rangeStart, rangeEnd})
    }

    for i in 7
    {
        var newRanges: Array'SeedRange
        for var idx = 0; idx < ranges.count; idx += 1
        {
            let seedRange = ranges[idx]
            #scope(Done)
            {
                for mapping in convert[i]
                {
                    if seedRange.start > mapping.sourceEnd or seedRange.end < mapping.sourceStart do
                        continue

                    // Keep the portions outside the mapped source range for the remaining rules.
                    if seedRange.start < mapping.sourceStart do
                        ranges.add({seedRange.start, mapping.sourceStart - 1})
                    if seedRange.end > mapping.sourceEnd do
                        ranges.add({mapping.sourceEnd + 1, seedRange.end})

                    let overlapStart     = Math.max(seedRange.start, mapping.sourceStart)
                    let overlapEnd       = Math.min(seedRange.end, mapping.sourceEnd)
                    let destinationStart = overlapStart - mapping.sourceStart + mapping.destinationStart
                    let destinationEnd   = overlapEnd - mapping.sourceStart + mapping.destinationStart
                    newRanges.add({destinationStart, destinationEnd})
                    break to Done
                }

                newRanges.add(seedRange)
            }
        }

        ranges = newRanges
    }

    var total = Swag.U64.Max
    for seedRange in ranges do
        total = Math.min(total, seedRange.start)

    Swag.assert(total == 69323688)
}
