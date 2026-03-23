#global fileprivate

// Advent of Code 2024 Day 1: keep one solution close to the direct puzzle
// mechanics, then cross-check it with a compile-time/interface-heavy variant.

const MaxLocationPairs = 1024
const MaxLocationId = 100000

const SampleInput =
"""3   4
4   3
2   5
1   3
3   9
3   3"""

const DenseInput = "10   10\r\n20   30\r\n20   20\r\n30   10\r\n"
const ActualInput = #include("../../../examples/modules/aoc2024/src/1.txt")

struct LocationLists
{
    count: u32
    left:  [MaxLocationPairs] u32
    right: [MaxLocationPairs] u32
}

struct HistorianReport
{
    pairCount:       u32
    totalDistance:   u64
    similarityScore: u64
}

interface IHistorianMetric
{
    mtd solve(bytes: const [..] u8)->u64;
}

struct DistanceMetric {}
struct SimilarityMetric {}

func isDigit(ch: u8)->bool
{
    return ch >= '0' and ch <= '9'
}

func isSpacing(ch: u8)->bool
{
    return ch == ' ''u8 or ch == '\t''u8 or ch == '\n''u8 or ch == '\r''u8
}

func skipSpacing(bytes: const [..] u8, index: *u32)
{
    while dref index < @countof(bytes) and isSpacing(bytes[dref index])
    {
        dref index += 1
    }
}

func parseNumber(bytes: const [..] u8, index: *u32)->u32
{
    @assert(dref index < @countof(bytes))
    @assert(isDigit(bytes[dref index]))

    var result: u32
    while dref index < @countof(bytes) and isDigit(bytes[dref index])
    {
        result = result * 10'u32 + cast(u32) (bytes[dref index] - '0')
        dref index += 1
    }

    return result
}

func parseLocationLists(bytes: const [..] u8)->LocationLists
{
    var result: LocationLists
    var index: u32

    while true
    {
        skipSpacing(bytes, &index)
        if index >= @countof(bytes) do
            break

        @assert(result.count < MaxLocationPairs)
        result.left[result.count] = parseNumber(bytes, &index)
        skipSpacing(bytes, &index)
        result.right[result.count] = parseNumber(bytes, &index)
        @assert(result.left[result.count] <= MaxLocationId)
        @assert(result.right[result.count] <= MaxLocationId)
        result.count += 1
    }

    return result
}

func distanceBetween(left, right: u32)->u32
{
    return left > right ? left - right : right - left
}

func buildFrequencies(leftFreq, rightFreq: [..] u32, lists: LocationLists)
{
    @assert(@countof(leftFreq) == MaxLocationId + 1)
    @assert(@countof(rightFreq) == MaxLocationId + 1)

    for lists.count
    {
        let index = cast(u32) @index
        leftFreq[lists.left[index]] += 1
        rightFreq[lists.right[index]] += 1
    }
}

func computeSimilarityFromFrequencies(leftFreq, rightFreq: const [..] u32)->u64
{
    var result: u64

    for @countof(leftFreq)
    {
        let value = cast(u32) @index
        result += cast(u64) value * cast(u64) leftFreq[value] * cast(u64) rightFreq[value]
    }

    return result
}

func computeDistanceFromFrequencies(leftFreq, rightFreq: [..] u32, pairCount: u32)->u64
{
    let limit = cast(u32) @countof(leftFreq)

    var leftValue: u32
    var rightValue: u32
    var result: u64

    for pairCount
    {
        while leftValue < limit and leftFreq[leftValue] == 0
        {
            leftValue += 1
        }

        while rightValue < limit and rightFreq[rightValue] == 0
        {
            rightValue += 1
        }

        @assert(leftValue < limit)
        @assert(rightValue < limit)
        result += cast(u64) distanceBetween(leftValue, rightValue)
        leftFreq[leftValue] -= 1
        rightFreq[rightValue] -= 1
    }

    return result
}

func solveClean(lists: LocationLists)->HistorianReport
{
    var leftFreq: [MaxLocationId + 1] u32
    var rightFreq: [MaxLocationId + 1] u32
    var result: HistorianReport

    buildFrequencies(leftFreq, rightFreq, lists)

    result.pairCount = lists.count
    result.similarityScore = computeSimilarityFromFrequencies(leftFreq, rightFreq)
    result.totalDistance = computeDistanceFromFrequencies(leftFreq, rightFreq, lists.count)
    return result
}

func copyValues(outValues: [..] u32, sourceValues: const [..] u32)
{
    @assert(@countof(outValues) == @countof(sourceValues))

    for @countof(sourceValues)
    {
        let index = cast(u32) @index
        outValues[index] = sourceValues[index]
    }
}

func sortValues(values: [..] u32)
{
    let count = cast(u32) @countof(values)

    var index = 1'u32
    while index < count
    {
        let value = values[index]
        var insertIndex = index

        while insertIndex > 0 and values[insertIndex - 1] > value
        {
            values[insertIndex] = values[insertIndex - 1]
            insertIndex -= 1
        }

        values[insertIndex] = value
        index += 1
    }
}

func lowerBound(sortedValues: const [..] u32, value: u32)->u32
{
    var first: u32
    var last = cast(u32) @countof(sortedValues)

    while first < last
    {
        let middle = first + (last - first) / 2
        if sortedValues[middle] < value
            do first = middle + 1
        else
            do last = middle
    }

    return first
}

func upperBound(sortedValues: const [..] u32, value: u32)->u32
{
    var first: u32
    var last = cast(u32) @countof(sortedValues)

    while first < last
    {
        let middle = first + (last - first) / 2
        if sortedValues[middle] <= value
            do first = middle + 1
        else
            do last = middle
    }

    return first
}

func countSortedOccurrences(sortedValues: const [..] u32, value: u32)->u32
{
    let first = lowerBound(sortedValues, value)
    let count = cast(u32) @countof(sortedValues)

    if first == count or sortedValues[first] != value do
        return 0

    return upperBound(sortedValues, value) - first
}

func computeDistanceBySorting(lists: LocationLists)->u64
{
    var leftSorted: [MaxLocationPairs] u32
    var rightSorted: [MaxLocationPairs] u32

    copyValues(leftSorted[until lists.count], lists.left[until lists.count])
    copyValues(rightSorted[until lists.count], lists.right[until lists.count])
    sortValues(leftSorted[until lists.count])
    sortValues(rightSorted[until lists.count])

    var result: u64
    for lists.count
    {
        let index = cast(u32) @index
        result += cast(u64) distanceBetween(leftSorted[index], rightSorted[index])
    }

    return result
}

func computeSimilarityBySorting(lists: LocationLists)->u64
{
    var rightSorted: [MaxLocationPairs] u32
    copyValues(rightSorted[until lists.count], lists.right[until lists.count])
    sortValues(rightSorted[until lists.count])

    let sortedSlice = rightSorted[until lists.count]
    var result: u64

    for lists.count
    {
        let index = cast(u32) @index
        let value = lists.left[index]
        let frequency = countSortedOccurrences(sortedSlice, value)
        result += cast(u64) value * cast(u64) frequency
    }

    return result
}

impl IHistorianMetric for DistanceMetric
{
    mtd impl solve(bytes: const [..] u8)->u64
    {
        let lists = parseLocationLists(bytes)
        return computeDistanceBySorting(lists)
    }
}

impl IHistorianMetric for SimilarityMetric
{
    mtd impl solve(bytes: const [..] u8)->u64
    {
        let lists = parseLocationLists(bytes)
        return computeSimilarityBySorting(lists)
    }
}

func runMetric(metric: IHistorianMetric, bytes: const [..] u8)->u64
{
    return metric.solve(bytes)
}

func solveWithLanguageFeatures(bytes: const [..] u8)->HistorianReport
{
    let lists = parseLocationLists(bytes)

    var distanceMetric: DistanceMetric
    var similarityMetric: SimilarityMetric
    var result: HistorianReport

    result.pairCount = lists.count
    result.totalDistance = runMetric(cast(IHistorianMetric) distanceMetric, bytes)
    result.similarityScore = runMetric(cast(IHistorianMetric) similarityMetric, bytes)
    return result
}

const SampleLanguageReport: HistorianReport = #run solveWithLanguageFeatures(cast(const [..] u8) SampleInput)
const DenseLanguageReport: HistorianReport = #run solveWithLanguageFeatures(cast(const [..] u8) DenseInput)
const ActualLanguageReport: HistorianReport = #run solveWithLanguageFeatures(cast(const [..] u8) ActualInput)

#test
{
    let sampleLists = parseLocationLists(cast(const [..] u8) SampleInput)
    let sampleClean = solveClean(sampleLists)
    let sampleFeatures = solveWithLanguageFeatures(cast(const [..] u8) SampleInput)

    @assert(sampleClean.pairCount == 6'u32)
    @assert(sampleClean.totalDistance == 11'u64)
    @assert(sampleClean.similarityScore == 31'u64)
    @assert(SampleLanguageReport.pairCount == 6'u32)
    @assert(SampleLanguageReport.totalDistance == 11'u64)
    @assert(SampleLanguageReport.similarityScore == 31'u64)
    @assert(sampleFeatures.pairCount == SampleLanguageReport.pairCount)
    @assert(sampleFeatures.totalDistance == SampleLanguageReport.totalDistance)
    @assert(sampleFeatures.similarityScore == SampleLanguageReport.similarityScore)
    @assert(sampleClean.totalDistance == sampleFeatures.totalDistance)
    @assert(sampleClean.similarityScore == sampleFeatures.similarityScore)
}

#test
{
    let denseLists = parseLocationLists(cast(const [..] u8) DenseInput)
    let denseClean = solveClean(denseLists)

    @assert(DenseLanguageReport.pairCount == 4'u32)
    @assert(DenseLanguageReport.totalDistance == 10'u64)
    @assert(DenseLanguageReport.similarityScore == 90'u64)
    @assert(denseClean.pairCount == DenseLanguageReport.pairCount)
    @assert(denseClean.totalDistance == DenseLanguageReport.totalDistance)
    @assert(denseClean.similarityScore == DenseLanguageReport.similarityScore)
}

#test
{
    let actualLists = parseLocationLists(cast(const [..] u8) ActualInput)
    let actualClean = solveClean(actualLists)

    @assert(ActualLanguageReport.pairCount == 1000'u32)
    @assert(ActualLanguageReport.totalDistance == 2_742_123'u64)
    @assert(ActualLanguageReport.similarityScore == 21_328_497'u64)
    @assert(actualClean.pairCount == ActualLanguageReport.pairCount)
    @assert(actualClean.totalDistance == ActualLanguageReport.totalDistance)
    @assert(actualClean.similarityScore == ActualLanguageReport.similarityScore)
}
