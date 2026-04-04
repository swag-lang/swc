#global fileprivate

// Advent of Code 2024 Day 5: validate page ordering rules and repair invalid
// updates through mutable/const references only, on fixed storage.

const MaxRules = 21'u32
const MaxUpdates = 6'u32
const MaxUpdatePages = 5'u32

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

impl Update
{
    #[Swag.Overload]
    mtd opIndex(index: u32) -> &s32
    {
        @assert(index < .count)
        return &.pages[index]
    }

    #[Swag.Overload]
    mtd const opIndex(index: u32) -> const &s32
    {
        @assert(index < .count)
        return &.pages[index]
    }

    mtd const middle()->s32
    {
        @assert(.count & 1'u32 == 1'u32)
        return .pages[.count / 2'u32]
    }
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

const TieBreakScenario: PrintQueueScenario =
{
    ruleCount: 2'u32,
    rules:
    [
        {before: 10, after: 30},
        {before: 20, after: 30},
    ],
    updateCount: 3'u32,
    updates:
    [
        {count: 3'u32, pages: [10, 20, 30, 0, 0]},
        {count: 3'u32, pages: [30, 20, 10, 0, 0]},
        {count: 3'u32, pages: [30, 10, 20, 0, 0]},
    ],
}

func clearUpdate(result: &Update)
{
    result.count = 0'u32
    for MaxUpdatePages
    {
        result.pages[cast(u32) @index] = 0
    }
}

func writePage(result: &s32, value: s32)
{
    result = value
}

func copyUpdate(result: &Update, source: const &Update)
{
    clearUpdate(result)
    result.count = source.count

    for source.count
    {
        let index = cast(u32) @index
        writePage(&result.pages[index], source[index])
    }
}

func findPageIndex(result: &u32, update: const &Update, page: s32)->bool
{
    result = 0'u32

    for update.count
    {
        let index = cast(u32) @index
        if update[index] == page
        {
            result = index
            return true
        }
    }

    return false
}

func hasRule(scenario: const &PrintQueueScenario, before, after: s32)->bool
{
    for scenario.ruleCount
    {
        let rule = &scenario.rules[cast(u32) @index]
        if rule.before == before and rule.after == after do
            return true
    }

    return false
}

func isOrderedUpdate(scenario: const &PrintQueueScenario, update: const &Update)->bool
{
    for scenario.ruleCount
    {
        let rule = &scenario.rules[cast(u32) @index]

        var beforeIndex: u32
        var afterIndex: u32
        let hasBefore = findPageIndex(&beforeIndex, update, rule.before)
        let hasAfter = findPageIndex(&afterIndex, update, rule.after)

        if hasBefore and hasAfter and beforeIndex > afterIndex do
            return false
    }

    return true
}

func hasIncomingRule(scenario: const &PrintQueueScenario, source: const &Update, used: [MaxUpdatePages] bool, candidateIndex: u32)->bool
{
    let candidatePage = source[candidateIndex]

    for source.count
    {
        let otherIndex = cast(u32) @index
        if used[otherIndex] or otherIndex == candidateIndex do
            continue

        let otherPage = source[otherIndex]
        if hasRule(scenario, otherPage, candidatePage) do
            return true
    }

    return false
}

func repairUpdate(result: &Update, scenario: const &PrintQueueScenario, source: const &Update)
{
    clearUpdate(result)
    result.count = source.count

    var used: [MaxUpdatePages] bool
    var writeIndex: u32

    while writeIndex < source.count
    {
        var found = false

        for candidateIndex in source.count
        {
            if used[candidateIndex] do
                continue
            if hasIncomingRule(scenario, source, used, candidateIndex) do
                continue

            writePage(&result.pages[writeIndex], source[candidateIndex])
            used[candidateIndex] = true
            writeIndex += 1'u32
            found = true
            break
        }

        @assert(found)
    }
}

func sameUpdate(lhs, rhs: const &Update)->bool
{
    if lhs.count != rhs.count do
        return false

    for lhs.count
    {
        let index = cast(u32) @index
        if lhs[index] != rhs[index] do
            return false
    }

    return true
}

func auditQueue(result: &QueueAudit, scenario: const &PrintQueueScenario)
{
    result.updateCount = scenario.updateCount

    for scenario.updateCount
    {
        let update = &scenario.updates[cast(u32) @index]

        if isOrderedUpdate(scenario, update)
        {
            result.orderedMiddleSum += update.middle()
            result.validUpdateCount += 1'u32
        }
        else
        {
            var repaired: Update
            repairUpdate(&repaired, scenario, update)
            result.correctedMiddleSum += repaired.middle()
        }
    }
}

#test
{
    var update: Update = {count: 3'u32, pages: [75, 47, 61, 0, 0]}
    let first = update[0]
    writePage(&update.pages[1], 53)

    var copied: Update
    copyUpdate(&copied, &update)

    @assert(first == 75)
    @assert(update[1] == 53)
    @assert(update.middle() == 53)
    @assert(sameUpdate(&copied, &update))

    let frozen = update
    @assert(frozen[2] == 61)
}

#test
{
    var sample = SampleScenario
    var sampleAudit: QueueAudit
    auditQueue(&sampleAudit, &sample)

    var repaired0: Update
    repairUpdate(&repaired0, &sample, &sample.updates[3])
    let expected0: Update = {count: 5'u32, pages: [97, 75, 47, 61, 53]}

    var repaired1: Update
    repairUpdate(&repaired1, &sample, &sample.updates[4])
    let expected1: Update = {count: 3'u32, pages: [61, 29, 13, 0, 0]}

    var repaired2: Update
    repairUpdate(&repaired2, &sample, &sample.updates[5])
    let expected2: Update = {count: 5'u32, pages: [97, 75, 47, 29, 13]}

    @assert(isOrderedUpdate(&sample, &sample.updates[0]))
    @assert(!isOrderedUpdate(&sample, &sample.updates[3]))
    @assert(sampleAudit.updateCount == 6'u32)
    @assert(sampleAudit.validUpdateCount == 3'u32)
    @assert(sampleAudit.orderedMiddleSum == 143)
    @assert(sampleAudit.correctedMiddleSum == 123)
    @assert(sameUpdate(&repaired0, &expected0))
    @assert(sameUpdate(&repaired1, &expected1))
    @assert(sameUpdate(&repaired2, &expected2))
}

#test
{
    var tieBreak = TieBreakScenario
    var tieBreakAudit: QueueAudit
    auditQueue(&tieBreakAudit, &tieBreak)

    var repairedA: Update
    repairUpdate(&repairedA, &tieBreak, &tieBreak.updates[1])
    let expectedA: Update = {count: 3'u32, pages: [20, 10, 30, 0, 0]}

    var repairedB: Update
    repairUpdate(&repairedB, &tieBreak, &tieBreak.updates[2])
    let expectedB: Update = {count: 3'u32, pages: [10, 20, 30, 0, 0]}

    @assert(tieBreakAudit.updateCount == 3'u32)
    @assert(tieBreakAudit.validUpdateCount == 1'u32)
    @assert(tieBreakAudit.orderedMiddleSum == 20)
    @assert(tieBreakAudit.correctedMiddleSum == 30)
    @assert(sameUpdate(&repairedA, &expectedA))
    @assert(sameUpdate(&repairedB, &expectedB))
}
