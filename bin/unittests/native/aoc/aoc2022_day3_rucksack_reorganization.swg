#global private

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
    rucksackCount:        u32
    groupCount:           u32
    misplacedPrioritySum: u64
    badgePrioritySum:     u64
}

interface ILineScorer
{
    mtd score(line: const [..] u8)->u32
}

interface IGroupScorer
{
    mtd score(firstMask, secondMask, thirdMask: u64)->u32
}

struct DuplicateScorer {}
struct BadgeScorer {}

func isLineBreak(ch: u8)->bool
{
    return ch == '\n'u8 or ch == '\r'u8
}

func isItemType(ch: u8)->bool
{
    return (ch >= 'a'u8 and ch <= 'z'u8) or (ch >= 'A'u8 and ch <= 'Z'u8)
}

func priorityOf(ch: u8)->u32
{
    Swag.assert(isItemType(ch))

    if ch >= 'a'u8 do
        return cast(u32, (ch - 'a'u8)) + 1'u32
    return cast(u32, (ch - 'A'u8)) + 27'u32
}

func maskForItem(ch: u8)->u64
{
    let priority = priorityOf(ch)
    return 1'u64 << cast(u64, (priority - 1'u32))
}

func priorityFromMask(mask: u64)->u32
{
    Swag.assert(mask != 0'u64)
    Swag.assert((mask & (mask - 1'u64)) == 0'u64)

    for index in 52
    {
        let bit = 1'u64 << cast(u64, index)
        if bit == mask do
            return cast(u32, index) + 1'u32
    }

    Swag.assert(false)
    return 0
}

func buildMask(line: const [..] u8)->u64
{
    var result: u64

    for index in line.count
    {
        let ch = line[index]
        Swag.assert(isItemType(ch))
        result |= maskForItem(ch)
    }

    return result
}

func duplicateMask(line: const [..] u8)->u64
{
    Swag.assert((line.count & 1'u64) == 0'u64)

    let half      = line.count / 2
    let leftMask  = buildMask(line[until half])
    let rightMask = buildMask(line[half to])
    return leftMask & rightMask
}

func badgeMask(first, second, third: const [..] u8)->u64
{
    return buildMask(first) & buildMask(second) & buildMask(third)
}

func solveClean(bytes: const [..] u8)->RucksackReport
{
    var result:     RucksackReport
    var lineStart:  u64
    var groupMasks: [3] u64
    var groupCount: u32

    for index in bytes.count
    {
        if isLineBreak(bytes[index]) or index == bytes.count - 1
        {
            var lineEnd = index
            if not isLineBreak(bytes[index]) do
                lineEnd = index + 1

            if lineEnd > lineStart
            {
                let line = bytes[lineStart until lineEnd]
                result.rucksackCount        += 1
                result.misplacedPrioritySum += cast(u64, priorityFromMask(duplicateMask(line)))

                groupMasks[groupCount] = buildMask(line)
                groupCount += 1
                if groupCount == 3
                {
                    result.groupCount       += 1
                    result.badgePrioritySum += cast(u64, priorityFromMask(groupMasks[0] & groupMasks[1] & groupMasks[2]))
                    groupCount              = 0
                }
            }

            lineStart = index + 1
        }
    }

    Swag.assert(groupCount == 0)
    return result
}

func(T) fill(values: [..] T, value: T)
{
    for index in values.count
    {
        values[index] = value
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

    Swag.assert(false)
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

    Swag.assert(false)
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
    var featureState = GroupState.NeedFirst
    var featureMasks:         [3] u64
}

#[Swag.Macro]
func forEachLine(bytes: const [..] u8, stmt: #code(line))
{
    var lineStart: u64
    for index in bytes.count
    {
        if isLineBreak(bytes[index]) or index == bytes.count - 1
        {
            var lineEnd = index
            if not isLineBreak(bytes[index]) do
                lineEnd = index + 1

            if lineEnd > lineStart
            {
                let lineLen = lineEnd - lineStart
                #inject(stmt, line = bytes[lineStart until lineStart + lineLen])
            }

            lineStart = index + 1
        }
    }
}

func solveWithLanguageFeatures(bytes: const [..] u8)->RucksackReport
{
    declareFeatureState()
    fill'(u64)(featureMasks, 0'u64)

    var duplicateScorer: DuplicateScorer
    var badgeScorer:     BadgeScorer
    let iDuplicate = cast(ILineScorer, duplicateScorer)
    let iBadge     = cast(IGroupScorer, badgeScorer)

    defer Swag.assert(featureState == GroupState.NeedFirst)

    forEachLine(bytes)
    {
        featureRucksackCount += 1
        featurePartOne       += cast(u64, iDuplicate.score(line))

        let slot = groupMaskIndex(featureState)
        featureMasks[slot] = buildMask(line)
        if featureState == GroupState.NeedThird
        {
            featureGroupCount += 1
            featurePartTwo    += cast(u64, iBadge.score(featureMasks[0], featureMasks[1], featureMasks[2]))
        }

        featureState = nextGroupState(featureState)
    }

    var result: RucksackReport
    result.rucksackCount        = featureRucksackCount
    result.groupCount           = featureGroupCount
    result.misplacedPrioritySum = featurePartOne
    result.badgePrioritySum     = featurePartTwo
    return result
}

const SampleFeatureReport:   RucksackReport = #run solveWithLanguageFeatures(cast(const [..] u8, SampleInput))
const CoverageFeatureReport: RucksackReport = #run solveWithLanguageFeatures(cast(const [..] u8, CoverageInput))
const EdgeFeatureReport:     RucksackReport = #run solveWithLanguageFeatures(cast(const [..] u8, EdgeInput))

#assert(#sizeof(GroupState) == 1)
#assert(#sizeof(RucksackReport) != 0)

#test
{
    let sampleBytes    = cast(const [..] u8, SampleInput)
    let sampleClean    = solveClean(sampleBytes)
    let sampleFeatures = solveWithLanguageFeatures(sampleBytes)

    Swag.require(sampleClean.rucksackCount == 6'u32)
    Swag.require(sampleClean.groupCount == 2'u32)
    Swag.require(sampleClean.misplacedPrioritySum == 157'u64)
    Swag.require(sampleClean.badgePrioritySum == 70'u64)
    Swag.require(SampleFeatureReport.rucksackCount == sampleClean.rucksackCount)
    Swag.require(SampleFeatureReport.groupCount == sampleClean.groupCount)
    Swag.require(SampleFeatureReport.misplacedPrioritySum == sampleClean.misplacedPrioritySum)
    Swag.require(SampleFeatureReport.badgePrioritySum == sampleClean.badgePrioritySum)
    Swag.require(sampleFeatures.misplacedPrioritySum == sampleClean.misplacedPrioritySum)
    Swag.require(sampleFeatures.badgePrioritySum == sampleClean.badgePrioritySum)
}

#test
{
    let coverageBytes    = cast(const [..] u8, CoverageInput)
    let coverageClean    = solveClean(coverageBytes)
    let coverageFeatures = solveWithLanguageFeatures(coverageBytes)

    Swag.require(coverageClean.rucksackCount == 6'u32)
    Swag.require(coverageClean.groupCount == 2'u32)
    Swag.require(coverageClean.misplacedPrioritySum == 159'u64)
    Swag.require(coverageClean.badgePrioritySum == 53'u64)
    Swag.require(CoverageFeatureReport.misplacedPrioritySum == coverageClean.misplacedPrioritySum)
    Swag.require(CoverageFeatureReport.badgePrioritySum == coverageClean.badgePrioritySum)
    Swag.require(coverageFeatures.misplacedPrioritySum == coverageClean.misplacedPrioritySum)
    Swag.require(coverageFeatures.badgePrioritySum == coverageClean.badgePrioritySum)
}

#test
{
    let edgeBytes    = cast(const [..] u8, EdgeInput)
    let edgeClean    = solveClean(edgeBytes)
    let edgeFeatures = solveWithLanguageFeatures(edgeBytes)

    Swag.require(edgeClean.rucksackCount == 3'u32)
    Swag.require(edgeClean.groupCount == 1'u32)
    Swag.require(edgeClean.misplacedPrioritySum == 39'u64)
    Swag.require(edgeClean.badgePrioritySum == 13'u64)
    Swag.require(EdgeFeatureReport.misplacedPrioritySum == edgeClean.misplacedPrioritySum)
    Swag.require(EdgeFeatureReport.badgePrioritySum == edgeClean.badgePrioritySum)
    Swag.require(edgeFeatures.misplacedPrioritySum == edgeClean.misplacedPrioritySum)
    Swag.require(edgeFeatures.badgePrioritySum == edgeClean.badgePrioritySum)

    let first  = cast(const [..] u8, "vJrwpWtwJgWrhcsFMMfFFhFp")
    let second = cast(const [..] u8, "jqHRNqRjqzjGDLGLrsFMfFZSrLrFZsSL")
    let third  = cast(const [..] u8, "PmmdzqPrVvPwwTWBwg")

    Swag.require(priorityOf('a') == 1)
    Swag.require(priorityOf('z') == 26)
    Swag.require(priorityOf('A') == 27)
    Swag.require(priorityOf('Z') == 52)
    Swag.require(priorityFromMask(maskForItem('p'u8)) == 16'u32)
    Swag.require(priorityFromMask(duplicateMask(first)) == 16'u32)
    Swag.require(priorityFromMask(badgeMask(first, second, third)) == 18'u32)

    var scratch: [3] u64
    fill(scratch, 7'u64)
    Swag.require(scratch[0] == 7'u64)
    Swag.require(scratch[1] == 7'u64)
    Swag.require(scratch[2] == 7'u64)
}
