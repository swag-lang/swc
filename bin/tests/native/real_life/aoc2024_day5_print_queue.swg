#global fileprivate

// Advent of Code 2024 Day 5: validate page ordering rules and repair
// invalid updates with fixed in-code data. This keeps the test standalone
// and leans on syntax coverage rather than large parsing inputs.

const MaxRules = 21
const MaxUpdates = 6
const MaxUpdatePages = 5

enum AuditKind: u8
{
    Ordered
    Corrected
}

struct RulePair
{
    before: s32
    after:  s32
}

struct Update
{
    count: u32
    pages: [MaxUpdatePages] s32
}

struct PrintQueueScenario
{
    ruleCount:   u32
    rules:       [MaxRules] RulePair
    updateCount: u32
    updates:     [MaxUpdates] Update
}

struct QueueAudit
{
    updateCount:        u32
    validUpdateCount:   u32
    orderedMiddleSum:   s32
    correctedMiddleSum: s32
}

const SampleScenario: PrintQueueScenario =
{
    ruleCount: 21'u32,
    rules:
    [
        {before: 47, after: 53},
        {before: 97, after: 13},
        {before: 97, after: 61},
        {before: 97, after: 47},
        {before: 75, after: 29},
        {before: 61, after: 13},
        {before: 75, after: 53},
        {before: 29, after: 13},
        {before: 97, after: 29},
        {before: 53, after: 29},
        {before: 61, after: 53},
        {before: 97, after: 53},
        {before: 61, after: 29},
        {before: 47, after: 13},
        {before: 75, after: 47},
        {before: 97, after: 75},
        {before: 47, after: 61},
        {before: 75, after: 61},
        {before: 47, after: 29},
        {before: 75, after: 13},
        {before: 53, after: 13},
    ],
    updateCount: 6'u32,
    updates:
    [
        {count: 5'u32, pages: [75, 47, 61, 53, 29]},
        {count: 5'u32, pages: [97, 61, 53, 29, 13]},
        {count: 3'u32, pages: [75, 29, 13, 0, 0]},
        {count: 5'u32, pages: [75, 97, 47, 61, 53]},
        {count: 3'u32, pages: [61, 13, 29, 0, 0]},
        {count: 5'u32, pages: [97, 13, 75, 29, 47]},
    ],
}

const CoverageScenario: PrintQueueScenario =
{
    ruleCount: 5'u32,
    rules:
    [
        {before: 10, after: 20},
        {before: 10, after: 30},
        {before: 20, after: 30},
        {before: 20, after: 40},
        {before: 30, after: 40},
    ],
    updateCount: 5'u32,
    updates:
    [
        {count: 3'u32, pages: [10, 20, 30, 0, 0]},
        {count: 3'u32, pages: [10, 20, 40, 0, 0]},
        {count: 3'u32, pages: [20, 10, 30, 0, 0]},
        {count: 3'u32, pages: [40, 30, 20, 0, 0]},
        {count: 3'u32, pages: [10, 30, 20, 0, 0]},
    ],
}

func hasRule(scenario: PrintQueueScenario, before, after: s32)->bool
{
    for scenario.ruleCount
    {
        let rule = scenario.rules[cast(u32) @index]
        if rule.before == before and rule.after == after do
            return true
    }

    return false
}

func comparePages(scenario: PrintQueueScenario, lhs, rhs: s32)->s32
{
    if hasRule(scenario, lhs, rhs) do
        return -1
    if hasRule(scenario, rhs, lhs) do
        return 1
    return lhs <=> rhs
}

func middlePage(update: Update)->s32
{
    defer @assert(update.count & 1 == 1)
    return update.pages[update.count / 2]
}

func hasSupportedWidth(update: Update)->bool
{
    switch update.count
    {
    case 3:
        fallthrough
    case 5:
        return true
    default:
        return false
    }
}

func isOrderedUpdate(scenario: PrintQueueScenario, update: Update)->bool
{
    @assert(hasSupportedWidth(update))

    for update.count
    {
        let firstIndex = cast(u32) @index
        let firstPage = update.pages[firstIndex]

        for secondIndex in firstIndex + 1 until update.count
        {
            if comparePages(scenario, firstPage, update.pages[secondIndex]) > 0 do
                return false
        }
    }

    return true
}

func repairUpdateClean(scenario: PrintQueueScenario, update: Update)->Update
{
    var result = update
    var index = 1'u32

    while index < result.count
    {
        let value = result.pages[index]
        var insertIndex = index

        while insertIndex > 0 and comparePages(scenario, value, result.pages[insertIndex - 1]) < 0
        {
            result.pages[insertIndex] = result.pages[insertIndex - 1]
            insertIndex -= 1
        }

        result.pages[insertIndex] = value
        index += 1
    }

    return result
}

func auditQueueClean(scenario: PrintQueueScenario)->QueueAudit
{
    var result: QueueAudit
    result.updateCount = scenario.updateCount

    for scenario.updateCount
    {
        let update = scenario.updates[cast(u32) @index]
        if isOrderedUpdate(scenario, update)
        {
            result.orderedMiddleSum += middlePage(update)
            result.validUpdateCount += 1'u32
        }
        else
        {
            let repaired = repairUpdateClean(scenario, update)
            result.correctedMiddleSum += middlePage(repaired)
        }
    }

    return result
}

func auditQueueWithLanguageFeatures(scenario: PrintQueueScenario)->QueueAudit
{
    var result: retval
    result.updateCount = scenario.updateCount

    for scenario.updateCount
    {
        let update = scenario.updates[cast(u32) @index]

        #[Swag.Complete]
        switch isOrderedUpdate(scenario, update)
        {
        case true:
            result.orderedMiddleSum += middlePage(update)
            result.validUpdateCount += 1'u32

        case false:
            let repaired = repairUpdateClean(scenario, update)
            result.correctedMiddleSum += middlePage(repaired)
        }
    }

    return result
}

#test
{
    let sampleClean = auditQueueClean(SampleScenario)
    let sampleFeatures = auditQueueWithLanguageFeatures(SampleScenario)

    @assert(hasSupportedWidth(SampleScenario.updates[0]))
    @assert(sampleClean.updateCount == 6'u32)
    @assert(sampleClean.validUpdateCount == 3'u32)
    @assert(sampleClean.orderedMiddleSum == 143)
    @assert(sampleClean.correctedMiddleSum == 123)
    @assert(sampleFeatures.updateCount == sampleClean.updateCount)
    @assert(sampleFeatures.validUpdateCount == sampleClean.validUpdateCount)
    @assert(sampleFeatures.orderedMiddleSum == sampleClean.orderedMiddleSum)
    @assert(sampleFeatures.correctedMiddleSum == sampleClean.correctedMiddleSum)
}

#test
{
    let coverageClean = auditQueueClean(CoverageScenario)
    let coverageFeatures = auditQueueWithLanguageFeatures(CoverageScenario)

    @assert(hasSupportedWidth(CoverageScenario.updates[0]))
    @assert(coverageClean.updateCount == 5'u32)
    @assert(coverageClean.validUpdateCount == 2'u32)
    @assert(coverageClean.orderedMiddleSum == 40)
    @assert(coverageClean.correctedMiddleSum == 70)
    @assert(coverageFeatures.updateCount == coverageClean.updateCount)
    @assert(coverageFeatures.validUpdateCount == coverageClean.validUpdateCount)
    @assert(coverageFeatures.orderedMiddleSum == coverageClean.orderedMiddleSum)
    @assert(coverageFeatures.correctedMiddleSum == coverageClean.correctedMiddleSum)
}
