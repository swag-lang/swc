#global fileprivate

// Advent of Code 2024 Day 2: keep one solver direct and data-oriented,
// then cross-check it with a caller-scope macro/mixin flavored variant.

const MaxReports = 1024
const MaxReportLevels = 16

const SampleInput =
"""7 6 4 2 1
1 2 7 8 9
9 7 6 2 1
1 3 2 4 5
8 6 4 4 1
1 3 6 7 9"""

const EdgeInput = "1 2 3 4\r\n1 3 2 4 5\r\n8 6 4 4 1\r\n9 7 6 2 1\r\n"
const ActualInput = #include("2.txt")

enum Trend: u8
{
    Unknown
    Rising
    Falling
}

struct Report
{
    count:  u32
    levels: [MaxReportLevels] s32
}

struct ReportBatch
{
    count:   u32
    reports: [MaxReports] Report
}

struct SafetyAudit
{
    reportCount:          u32
    safeWithoutDampener:  u32
    safeWithDampener:     u32
}

func isDigit(ch: u8)->bool
{
    return ch >= '0' and ch <= '9'
}

func isValidDelta(delta: s32)->bool
{
    return delta != 0 and @abs(delta) <= 3
}

func deltaTrend(delta: s32)->Trend
{
    return delta > 0 ? Trend.Rising : Trend.Falling
}

func parseReports(bytes: const [..] u8)->ReportBatch
{
    var result: ReportBatch
    var current: Report
    var value: s32
    var readingNumber = false

    for @countof(bytes)
    {
        let ch = bytes[@index]
        if isDigit(ch)
        {
            value = value * 10 + cast(s32) (ch - '0')
            readingNumber = true
            continue
        }

        if ch == ' ''u8 or ch == '\r''u8 or ch == '\n''u8
        {
            if readingNumber
            {
                @assert(current.count < MaxReportLevels)
                current.levels[current.count] = value
                current.count += 1
                value = 0
                readingNumber = false
            }

            if ch == '\n''u8 and current.count != 0
            {
                @assert(result.count < MaxReports)
                result.reports[result.count] = current
                result.count += 1
                current.count = 0
            }

            continue
        }

        @assert(false)
    }

    if readingNumber
    {
        @assert(current.count < MaxReportLevels)
        current.levels[current.count] = value
        current.count += 1
    }

    if current.count != 0
    {
        @assert(result.count < MaxReports)
        result.reports[result.count] = current
        result.count += 1
    }

    return result
}

func isSafeReport(report: Report, skippedIndex: s32)->bool
{
    var trend = Trend.Unknown
    var previous: s32
    var havePrevious = false

    for report.count
    {
        let rawIndex = cast(u32) @index
        if cast(s32) rawIndex == skippedIndex do
            continue

        let level = report.levels[rawIndex]
        if !havePrevious
        {
            previous = level
            havePrevious = true
            continue
        }

        let delta = level - previous
        if !isValidDelta(delta) do
            return false

        let currentTrend = deltaTrend(delta)
        if trend != Trend.Unknown and currentTrend != trend do
            return false

        trend = currentTrend
        previous = level
    }

    return true
}

func isSafeWithProblemDampener(report: Report)->bool
{
    if isSafeReport(report, -1) do
        return true

    for report.count
    {
        let skippedIndex = cast(s32) @index
        if isSafeReport(report, skippedIndex) do
            return true
    }

    return false
}

func auditReportsClean(batch: ReportBatch)->SafetyAudit
{
    var result: SafetyAudit
    result.reportCount = batch.count

    for batch.count
    {
        let index = cast(u32) @index
        let report = batch.reports[index]
        let strictSafe = isSafeReport(report, -1)
        if strictSafe do
            result.safeWithoutDampener += 1

        if strictSafe or isSafeWithProblemDampener(report) do
            result.safeWithDampener += 1
    }

    return result
}

#[Swag.Mixin]
func declareFeatureState()
{
    var featureTrend = Trend.Unknown
    var featurePrevious: s32
    var featureHasPrevious = false
    var featureVisitedLevels: u32
    var featureSafe = true
}

#[Swag.Mixin]
func noteFeatureLevel(level: s32)
{
    featureVisitedLevels += 1

    if featureSafe
    {
        if let delta = level - featurePrevious where featureHasPrevious
        {
            if !isValidDelta(delta)
            {
                featureSafe = false
            }
            else
            {
                let currentTrend = deltaTrend(delta)
                switch featureTrend
                {
                case Trend.Unknown:
                    featureTrend = currentTrend
                    break

                case Trend.Rising where currentTrend == Trend.Rising:
                    break

                case Trend.Falling where currentTrend == Trend.Falling:
                    break

                default:
                    featureSafe = false
                    break
                }
            }
        }

        featurePrevious = level
        featureHasPrevious = true
    }
}

#[Swag.Macro]
func visitReportLevels(report: Report, skippedIndex: s32, stmt: #code void)
{
    for report.count
    {
        if cast(s32) @index == skippedIndex do
            continue

        let #alias0 = report.levels[cast(u32) @index]
        let #alias1 = cast(u32) @index
        #inject(stmt)
    }
}

func isSafeReportWithLanguageFeatures(report: Report, skippedIndex: s32)->bool
{
    declareFeatureState()
    defer @assert(featureVisitedLevels <= report.count)

    visitReportLevels(|level, rawIndex| report, skippedIndex)
    {
        @assert(rawIndex < report.count)
        noteFeatureLevel(level)
    }

    return featureSafe
}

func isSafeWithProblemDampenerLanguageFeatures(report: Report)->bool
{
    if isSafeReportWithLanguageFeatures(report, -1) do
        return true

    for report.count
    {
        let skippedIndex = cast(s32) @index
        if isSafeReportWithLanguageFeatures(report, skippedIndex) do
            return true
    }

    return false
}

func auditReportsWithLanguageFeatures(batch: ReportBatch)->SafetyAudit
{
    var result: SafetyAudit
    result.reportCount = batch.count

    for batch.count
    {
        let index = cast(u32) @index
        let report = batch.reports[index]
        let strictSafe = isSafeReportWithLanguageFeatures(report, -1)
        if strictSafe do
            result.safeWithoutDampener += 1

        if strictSafe or isSafeWithProblemDampenerLanguageFeatures(report) do
            result.safeWithDampener += 1
    }

    return result
}

#test
{
    let sampleBatch = parseReports(cast(const [..] u8) SampleInput)
    let sampleClean = auditReportsClean(sampleBatch)
    let sampleFeatures = auditReportsWithLanguageFeatures(sampleBatch)

    @assert(sampleBatch.count == 6'u32)
    @assert(isSafeReport(sampleBatch.reports[0], -1))
    @assert(!isSafeReport(sampleBatch.reports[1], -1))
    @assert(!isSafeWithProblemDampener(sampleBatch.reports[2]))
    @assert(isSafeWithProblemDampener(sampleBatch.reports[3]))
    @assert(isSafeWithProblemDampener(sampleBatch.reports[4]))
    @assert(isSafeReportWithLanguageFeatures(sampleBatch.reports[0], -1))
    @assert(!isSafeReportWithLanguageFeatures(sampleBatch.reports[1], -1))
    @assert(!isSafeWithProblemDampenerLanguageFeatures(sampleBatch.reports[2]))
    @assert(sampleClean.reportCount == 6'u32)
    @assert(sampleClean.safeWithoutDampener == 2'u32)
    @assert(sampleClean.safeWithDampener == 4'u32)
    @assert(sampleFeatures.reportCount == sampleClean.reportCount)
    @assert(sampleFeatures.safeWithoutDampener == sampleClean.safeWithoutDampener)
    @assert(sampleFeatures.safeWithDampener == sampleClean.safeWithDampener)
}

#test
{
    let edgeBatch = parseReports(cast(const [..] u8) EdgeInput)
    let edgeClean = auditReportsClean(edgeBatch)
    let edgeFeatures = auditReportsWithLanguageFeatures(edgeBatch)

    @assert(edgeBatch.count == 4'u32)
    @assert(edgeClean.safeWithoutDampener == 1'u32)
    @assert(edgeClean.safeWithDampener == 3'u32)
    @assert(edgeFeatures.reportCount == edgeClean.reportCount)
    @assert(edgeFeatures.safeWithoutDampener == edgeClean.safeWithoutDampener)
    @assert(edgeFeatures.safeWithDampener == edgeClean.safeWithDampener)
}

#test
{
    let actualBatch = parseReports(cast(const [..] u8) ActualInput)
    let actualClean = auditReportsClean(actualBatch)
    let actualFeatures = auditReportsWithLanguageFeatures(actualBatch)

    @assert(actualClean.reportCount == 1000'u32)
    @assert(actualClean.safeWithoutDampener == 549'u32)
    @assert(actualClean.safeWithDampener == 589'u32)
    @assert(actualFeatures.reportCount == actualClean.reportCount)
    @assert(actualFeatures.safeWithoutDampener == actualClean.safeWithoutDampener)
    @assert(actualFeatures.safeWithDampener == actualClean.safeWithDampener)
}
