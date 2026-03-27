#global fileprivate

// Advent of Code 2023 Day 1: extract calibration values from lines that
// contain digits (part 1) or digits and spelled-out words (part 2), then
// cross-check a clean scanner with a mixin/macro/interface-heavy variant.

const DigitCount = 9

const SampleInputA =
"""1abc2
pqr3stu8vwx
a1b2c3d4e5f
treb7uchet"""

const SampleInputB =
"""two1nine
eightwothree
abcone2threexyz
xtwone3four
4nineeightseven2
zoneight234
7pqrstsixteen"""

const EdgeOverlap  = "eightwo"
const EdgeAllWords = "onetwothreefourfivesixseveneightnine"
const EdgeEmpty    = "abcxyz"
const EdgeSingle   = "7"

const CoverageInput =
"""abc1def
2ghi3
fourjkl
fiveight
sevenine
twone
nineight1twothree
oneone"""

struct CalibrationResult
{
    digitOnly: u64
    withWords: u64
}

interface IDigitFinder
{
    mtd findFirst(line: const [..] u8)->s32;
    mtd findLast(line: const [..] u8)->s32;
}

struct DigitOnlyFinder {}
struct WordAwareFinder {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const SpelledDigits: [DigitCount] string = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]

func isDigit(ch: u8)->bool
{
    return ch >= '0' and ch <= '9'
}

func digitValue(ch: u8)->s32
{
    return cast(s32) (ch - '0')
}

func isNewline(ch: u8)->bool
{
    return ch == '\n''u8 or ch == '\r''u8
}

func matchLiteral(bytes: const [..] u8, pos: u64, lit: string)->bool
{
    let litBytes = cast(const [..] u8) lit
    if pos + @countof(litBytes) > @countof(bytes) do
        return false
    for @countof(litBytes)
    {
        if bytes[pos + @index] != litBytes[@index] do
            return false
    }
    return true
}

func spelledDigitAt(bytes: const [..] u8, pos: u64)->s32
{
    for DigitCount
    {
        if matchLiteral(bytes, pos, SpelledDigits[@index]) do
            return cast(s32) @index + 1
    }
    return -1
}

// ---------------------------------------------------------------------------
// Clean approach: direct line-by-line scanning
// ---------------------------------------------------------------------------

func calibrationValueDigitOnly(line: const [..] u8)->u32
{
    var first = -1's32
    var last  = -1's32

    for @countof(line)
    {
        let ch = line[@index]
        if isDigit(ch)
        {
            let d = digitValue(ch)
            if first < 0 do
                first = d
            last = d
        }
    }

    if first < 0 do
        return 0
    return cast(u32) (first * 10 + last)
}

func calibrationValueWithWords(line: const [..] u8)->u32
{
    var first = -1's32
    var last  = -1's32

    for @countof(line)
    {
        var d = -1's32
        let ch = line[@index]

        if isDigit(ch) do
            d = digitValue(ch)
        else do
            d = spelledDigitAt(line, @index)

        if d >= 0
        {
            if first < 0 do
                first = d
            last = d
        }
    }

    if first < 0 do
        return 0
    return cast(u32) (first * 10 + last)
}

func solveClean(bytes: const [..] u8)->CalibrationResult
{
    var result: CalibrationResult
    var lineStart: u64

    for @countof(bytes)
    {
        if isNewline(bytes[@index]) or @index == @countof(bytes) - 1
        {
            var lineEnd = @index
            if !isNewline(bytes[@index]) do
                lineEnd = @index + 1

            if lineEnd > lineStart
            {
                let lineLen = lineEnd - lineStart
                let line = bytes[lineStart until lineStart + lineLen]
                result.digitOnly += cast(u64) calibrationValueDigitOnly(line)
                result.withWords += cast(u64) calibrationValueWithWords(line)
            }

            lineStart = @index + 1
        }
    }

    return result
}

// ---------------------------------------------------------------------------
// Language-features approach: interfaces, mixins, macros
// ---------------------------------------------------------------------------

impl IDigitFinder for DigitOnlyFinder
{
    mtd impl findFirst(line: const [..] u8)->s32
    {
        for @countof(line)
        {
            if isDigit(line[@index]) do
                return digitValue(line[@index])
        }
        return -1
    }

    mtd impl findLast(line: const [..] u8)->s32
    {
        for #reverse @countof(line)
        {
            if isDigit(line[@index]) do
                return digitValue(line[@index])
        }
        return -1
    }
}

impl IDigitFinder for WordAwareFinder
{
    mtd impl findFirst(line: const [..] u8)->s32
    {
        for @countof(line)
        {
            if isDigit(line[@index]) do
                return digitValue(line[@index])
            let w = spelledDigitAt(line, @index)
            if w >= 0 do
                return w
        }
        return -1
    }

    mtd impl findLast(line: const [..] u8)->s32
    {
        for #reverse @countof(line)
        {
            if isDigit(line[@index]) do
                return digitValue(line[@index])
            let w = spelledDigitAt(line, @index)
            if w >= 0 do
                return w
        }
        return -1
    }
}

#[Swag.Mixin]
func declareLineScanner()
{
    var scanLineStart: u64
    var scanDigitSum:  u64
    var scanWordSum:   u64
}

func accumulateLine(line: const [..] u8, finder: IDigitFinder, target: *u64)
{
    let first = finder.findFirst(line)
    let last  = finder.findLast(line)
    if first >= 0 do
        dref target += cast(u64) (first * 10 + last)
}

#[Swag.Macro]
func forEachLine(bytes: const [..] u8, stmt: #code void)
{
    var lineStart: u64
    for @countof(bytes)
    {
        if isNewline(bytes[@index]) or @index == @countof(bytes) - 1
        {
            var lineEnd = @index
            if !isNewline(bytes[@index]) do
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

func solveWithLanguageFeatures(bytes: const [..] u8)->CalibrationResult
{
    declareLineScanner()

    var digitFinder: DigitOnlyFinder
    var wordFinder:  WordAwareFinder
    let iDigit = cast(IDigitFinder) digitFinder
    let iWord  = cast(IDigitFinder) wordFinder

    defer @assert(scanDigitSum >= 0)

    forEachLine(|line| bytes)
    {
        accumulateLine(line, iDigit, &scanDigitSum)
        accumulateLine(line, iWord, &scanWordSum)
    }

    var result: CalibrationResult
    result.digitOnly = scanDigitSum
    result.withWords = scanWordSum
    return result
}

// ---------------------------------------------------------------------------
// Compile-time evaluation
// ---------------------------------------------------------------------------

const SampleAResult: CalibrationResult = #run solveWithLanguageFeatures(cast(const [..] u8) SampleInputA)
const SampleBResult: CalibrationResult = #run solveWithLanguageFeatures(cast(const [..] u8) SampleInputB)
const CoverageResult: CalibrationResult = #run solveWithLanguageFeatures(cast(const [..] u8) CoverageInput)

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#test
{
    let cleanA = solveClean(cast(const [..] u8) SampleInputA)
    let featA  = solveWithLanguageFeatures(cast(const [..] u8) SampleInputA)

    @assert(cleanA.digitOnly == 142'u64)
    @assert(cleanA.withWords == 142'u64)
    @assert(SampleAResult.digitOnly == 142'u64)
    @assert(SampleAResult.withWords == 142'u64)
    @assert(featA.digitOnly == cleanA.digitOnly)
    @assert(featA.withWords == cleanA.withWords)
}

#test
{
    let cleanB = solveClean(cast(const [..] u8) SampleInputB)
    let featB  = solveWithLanguageFeatures(cast(const [..] u8) SampleInputB)

    @assert(cleanB.withWords == 281'u64)
    @assert(SampleBResult.withWords == 281'u64)
    @assert(featB.digitOnly == cleanB.digitOnly)
    @assert(featB.withWords == cleanB.withWords)
}

#test
{
    // Overlapping spelled digits: "eightwo" -> first=8, last=2 -> 82
    let overlapLine = cast(const [..] u8) EdgeOverlap
    @assert(calibrationValueWithWords(overlapLine) == 82'u32)
    @assert(calibrationValueDigitOnly(overlapLine) == 0'u32)

    // All spelled: "onetwothreefourfivesixseveneightnine" -> first=1, last=9 -> 19
    let allWordsLine = cast(const [..] u8) EdgeAllWords
    @assert(calibrationValueWithWords(allWordsLine) == 19'u32)
    @assert(calibrationValueDigitOnly(allWordsLine) == 0'u32)

    // No digits at all
    let emptyLine = cast(const [..] u8) EdgeEmpty
    @assert(calibrationValueWithWords(emptyLine) == 0'u32)
    @assert(calibrationValueDigitOnly(emptyLine) == 0'u32)

    // Single digit
    let singleLine = cast(const [..] u8) EdgeSingle
    @assert(calibrationValueWithWords(singleLine) == 77'u32)
    @assert(calibrationValueDigitOnly(singleLine) == 77'u32)
}

#test
{
    let cleanC = solveClean(cast(const [..] u8) CoverageInput)
    let featC  = solveWithLanguageFeatures(cast(const [..] u8) CoverageInput)

    @assert(CoverageResult.digitOnly == cleanC.digitOnly)
    @assert(CoverageResult.withWords == cleanC.withWords)
    @assert(featC.digitOnly == cleanC.digitOnly)
    @assert(featC.withWords == cleanC.withWords)
}
