#global fileprivate

// Advent of Code 2022 - Day 3: Rucksack Reorganization
//
// Keep one solution close to the puzzle mechanics with bitmasks, then
// cross-check it with a feature-heavy path that uses mixins, macros,
// interfaces, generics, enums, and compile-time execution.

const SampleInput =
"""vJrwpWtwJgWrhcsFMMfFFhFp
   jqHRNqRjqzjGDLGLrsFMfFZSrLrFZsSL
   PmmdzqPrVvPwwTWBwg
   wMqvLMZHhHMvwLHjbvcjnnSBnvTQFn
   ttgJtRGJQctTZtZT
   CrZsJsPPZsGzwwsLwLmpwMDw"""

const CoverageInput =
"""abca
   daea
   faag
   ZkZm
   qZZr
   sZtZ"""

const EdgeInput = "ammb\r\ncmmd\r\nemmf\r\n"

enum GroupState: u8
{
    NeedFirst
    NeedSecond
    NeedThird
}

struct RucksackReport
{
    rucksackCount:       u32
    groupCount:          u32
    misplacedPrioritySum:u64
    badgePrioritySum:    u64
}

interface ILineScorer
{
    mtd score(line: const [..] u8)->u32;
}

interface IGroupScorer
{
    mtd score(firstMask, secondMask, thirdMask: u64)->u32;
}

struct DuplicateScorer {}
struct BadgeScorer {}

func isLineBreak(ch: u8)->bool
{
    return ch == '\n''u8 or ch == '\r''u8
}

func isItemType(ch: u8)->bool
{
    return (ch >= 'a''u8 and ch <= 'z''u8) or (ch >= 'A''u8 and ch <= 'Z''u8)
}

func priorityOf(ch: u8)->u32
{
    @assert(isItemType(ch))

    if ch >= 'a''u8 do
        return cast(u32) (ch - 'a''u8) + 1'u32
    return cast(u32) (ch - 'A''u8) + 27'u32
}

func maskForItem(ch: u8)->u64
{
    let priority = priorityOf(ch)
    return 1'u64 << cast(u64) (priority - 1'u32)
}

func priorityFromMask(mask: u64)->u32
{
    @assert(mask != 0'u64)
    @assert((mask & (mask - 1'u64)) == 0'u64)

    for 52
    {
        let bit = 1'u64 << cast(u64) @index
        if bit == mask do
            return cast(u32) @index + 1'u32
    }

    @assert(false)
    return 0
}

func buildMask(line: const [..] u8)->u64
{
    var result: u64

    for @countof(line)
    {
        let ch = line[@index]
        @assert(isItemType(ch))
        result |= maskForItem(ch)
    }

    return result
}

func duplicateMask(line: const [..] u8)->u64
{
    @assert((@countof(line) & 1'u64) == 0'u64)

    let half = @countof(line) / 2
    let leftMask = buildMask(line[until half])
    let rightMask = buildMask(line[half to])
    return leftMask & rightMask
}

func badgeMask(first, second, third: const [..] u8)->u64
{
    return buildMask(first) & buildMask(second) & buildMask(third)
}

func solveClean(bytes: const [..] u8)->RucksackReport
{
    var result: RucksackReport
    var lineStart: u64
    var groupMasks: [3] u64
    var groupCount: u32

    for @countof(bytes)
    {
        if isLineBreak(bytes[@index]) or @index == @countof(bytes) - 1
        {
            var lineEnd = @index
            if !isLineBreak(bytes[@index]) do
                lineEnd = @index + 1

            if lineEnd > lineStart
            {
                let line = bytes[lineStart until lineEnd]
                result.rucksackCount += 1
                result.misplacedPrioritySum += cast(u64) priorityFromMask(duplicateMask(line))

                groupMasks[groupCount] = buildMask(line)
                groupCount += 1
                if groupCount == 3
                {
                    result.groupCount += 1
                    result.badgePrioritySum += cast(u64) priorityFromMask(groupMasks[0] & groupMasks[1] & groupMasks[2])
                    groupCount = 0
                }
            }

            lineStart = @index + 1
        }
    }

    @assert(groupCount == 0)
    return result
}

func(T) fill(values: [..] T, value: T)
{
    for @countof(values)
    {
        values[@index] = value
    }
}

func groupMaskIndex(state: GroupState)->u32
{
    switch state
    {
    case GroupState.NeedFirst:
        return 0

    case GroupState.NeedSecond:
        return 1

    case GroupState.NeedThird:
        return 2
    }

    @assert(false)
    return 0
}

func nextGroupState(state: GroupState)->GroupState
{
    switch state
    {
    case GroupState.NeedFirst:
        return GroupState.NeedSecond

    case GroupState.NeedSecond:
        return GroupState.NeedThird

    case GroupState.NeedThird:
        return GroupState.NeedFirst
    }

    @assert(false)
    return GroupState.NeedFirst
}

impl ILineScorer for DuplicateScorer
{
    mtd impl score(line: const [..] u8)->u32
    {
        return priorityFromMask(duplicateMask(line))
    }
}

impl IGroupScorer for BadgeScorer
{
    mtd impl score(firstMask, secondMask, thirdMask: u64)->u32
    {
        return priorityFromMask(firstMask & secondMask & thirdMask)
    }
}

#[Swag.Mixin]
func declareFeatureState()
{
    var featureRucksackCount: u32
    var featureGroupCount:    u32
    var featurePartOne:       u64
    var featurePartTwo:       u64
    var featureState          = GroupState.NeedFirst
    var featureMasks:         [3] u64
}

#[Swag.Macro]
func forEachLine(bytes: const [..] u8, stmt: #code void)
{
    var lineStart: u64
    for @countof(bytes)
    {
        if isLineBreak(bytes[@index]) or @index == @countof(bytes) - 1
        {
            var lineEnd = @index
            if !isLineBreak(bytes[@index]) do
                lineEnd = @index + 1

            if lineEnd > lineStart
            {
                let lineLen = lineEnd - lineStart
                let #alias0 = bytes[lineStart until lineStart + lineLen]
                #inject(stmt)
            }

            lineStart = @index + 1
        }
    }
}

func solveWithLanguageFeatures(bytes: const [..] u8)->RucksackReport
{
    declareFeatureState()
    fill'(u64)(featureMasks, 0'u64)

    var duplicateScorer: DuplicateScorer
    var badgeScorer:     BadgeScorer
    let iDuplicate = cast(ILineScorer) duplicateScorer
    let iBadge     = cast(IGroupScorer) badgeScorer

    defer @assert(featureState == GroupState.NeedFirst)

    forEachLine(|line| bytes)
    {
        featureRucksackCount += 1
        featurePartOne += cast(u64) iDuplicate.score(line)

        let slot = groupMaskIndex(featureState)
        featureMasks[slot] = buildMask(line)
        if featureState == GroupState.NeedThird
        {
            featureGroupCount += 1
            featurePartTwo += cast(u64) iBadge.score(featureMasks[0], featureMasks[1], featureMasks[2])
        }

        featureState = nextGroupState(featureState)
    }

    var result: RucksackReport
    result.rucksackCount = featureRucksackCount
    result.groupCount = featureGroupCount
    result.misplacedPrioritySum = featurePartOne
    result.badgePrioritySum = featurePartTwo
    return result
}

const SampleFeatureReport: RucksackReport = #run solveWithLanguageFeatures(cast(const [..] u8) SampleInput)
const CoverageFeatureReport: RucksackReport = #run solveWithLanguageFeatures(cast(const [..] u8) CoverageInput)
const EdgeFeatureReport: RucksackReport = #run solveWithLanguageFeatures(cast(const [..] u8) EdgeInput)

#assert(#sizeof(GroupState) == 1)
#assert(#sizeof(RucksackReport) != 0)

#test
{
    let sampleBytes = cast(const [..] u8) SampleInput
    let sampleClean = solveClean(sampleBytes)
    let sampleFeatures = solveWithLanguageFeatures(sampleBytes)

    @assert(sampleClean.rucksackCount == 6'u32)
    @assert(sampleClean.groupCount == 2'u32)
    @assert(sampleClean.misplacedPrioritySum == 157'u64)
    @assert(sampleClean.badgePrioritySum == 70'u64)
    @assert(SampleFeatureReport.rucksackCount == sampleClean.rucksackCount)
    @assert(SampleFeatureReport.groupCount == sampleClean.groupCount)
    @assert(SampleFeatureReport.misplacedPrioritySum == sampleClean.misplacedPrioritySum)
    @assert(SampleFeatureReport.badgePrioritySum == sampleClean.badgePrioritySum)
    @assert(sampleFeatures.misplacedPrioritySum == sampleClean.misplacedPrioritySum)
    @assert(sampleFeatures.badgePrioritySum == sampleClean.badgePrioritySum)
}

#test
{
    let coverageBytes = cast(const [..] u8) CoverageInput
    let coverageClean = solveClean(coverageBytes)
    let coverageFeatures = solveWithLanguageFeatures(coverageBytes)

    @assert(coverageClean.rucksackCount == 6'u32)
    @assert(coverageClean.groupCount == 2'u32)
    @assert(coverageClean.misplacedPrioritySum == 159'u64)
    @assert(coverageClean.badgePrioritySum == 53'u64)
    @assert(CoverageFeatureReport.misplacedPrioritySum == coverageClean.misplacedPrioritySum)
    @assert(CoverageFeatureReport.badgePrioritySum == coverageClean.badgePrioritySum)
    @assert(coverageFeatures.misplacedPrioritySum == coverageClean.misplacedPrioritySum)
    @assert(coverageFeatures.badgePrioritySum == coverageClean.badgePrioritySum)
}

#test
{
    let edgeBytes = cast(const [..] u8) EdgeInput
    let edgeClean = solveClean(edgeBytes)
    let edgeFeatures = solveWithLanguageFeatures(edgeBytes)

    @assert(edgeClean.rucksackCount == 3'u32)
    @assert(edgeClean.groupCount == 1'u32)
    @assert(edgeClean.misplacedPrioritySum == 39'u64)
    @assert(edgeClean.badgePrioritySum == 13'u64)
    @assert(EdgeFeatureReport.misplacedPrioritySum == edgeClean.misplacedPrioritySum)
    @assert(EdgeFeatureReport.badgePrioritySum == edgeClean.badgePrioritySum)
    @assert(edgeFeatures.misplacedPrioritySum == edgeClean.misplacedPrioritySum)
    @assert(edgeFeatures.badgePrioritySum == edgeClean.badgePrioritySum)

    let first = cast(const [..] u8) "vJrwpWtwJgWrhcsFMMfFFhFp"
    let second = cast(const [..] u8) "jqHRNqRjqzjGDLGLrsFMfFZSrLrFZsSL"
    let third = cast(const [..] u8) "PmmdzqPrVvPwwTWBwg"

    @assert(priorityOf('a''u8) == 1'u32)
    @assert(priorityOf('z''u8) == 26'u32)
    @assert(priorityOf('A''u8) == 27'u32)
    @assert(priorityOf('Z''u8) == 52'u32)
    @assert(priorityFromMask(maskForItem('p''u8)) == 16'u32)
    @assert(priorityFromMask(duplicateMask(first)) == 16'u32)
    @assert(priorityFromMask(badgeMask(first, second, third)) == 18'u32)

    var scratch: [3] u64
    fill'(u64)(scratch, 7'u64)
    @assert(scratch[0] == 7'u64)
    @assert(scratch[1] == 7'u64)
    @assert(scratch[2] == 7'u64)
}
