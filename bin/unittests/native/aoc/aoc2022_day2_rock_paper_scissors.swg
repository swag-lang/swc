#global private

// Advent of Code 2022 - Day 2: Rock Paper Scissors
//
// Keep one solver direct and data-oriented, then cross-check it with a
// feature-oriented path that uses macros, mixins, interfaces, and #run.

const MaxRounds = 64

const SampleInput =
    """A Y
   B X
   C Z"""

const CoverageInput =
    """A X
   A Y
   A Z
   B X
   B Y
   B Z
   C X
   C Y
   C Z"""

const EdgeInput = "A Z\r\nC X\r\n"

enum Shape: u8
{
    Rock     = 1
    Paper    = 2
    Scissors = 3
}

enum Outcome: u8
{
    Lose = 0
    Draw = 3
    Win  = 6
}

struct GuideRound
{
    opponentToken: u8
    codeToken:     u8
}

struct StrategyGuide
{
    count:  u32
    rounds: [MaxRounds] GuideRound
}

struct ScoreSummary
{
    partOne: u32
    partTwo: u32
}

interface IRoundScorer
{
    mtd score(opponentToken: u8, codeToken: u8)->u32
}

struct PartOneScorer {}
struct PartTwoScorer {}

func isOpponentToken(ch: u8)->bool
{
    return ch == 'A'u8 or ch == 'B'u8 or ch == 'C'u8
}

func isCodeToken(ch: u8)->bool
{
    return ch == 'X'u8 or ch == 'Y'u8 or ch == 'Z'u8
}

func decodeOpponent(token: u8)->Shape
{
    switch token
    {
    case 'A':
        return Shape.Rock

    case 'B':
        return Shape.Paper

    case 'C':
        return Shape.Scissors
    }

    Swag.assert(false)
    return Shape.Rock
}

func decodePartOneShape(token: u8)->Shape
{
    switch token
    {
    case 'X':
        return Shape.Rock

    case 'Y':
        return Shape.Paper

    case 'Z':
        return Shape.Scissors
    }

    Swag.assert(false)
    return Shape.Rock
}

func decodeDesiredOutcome(token: u8)->Outcome
{
    switch token
    {
    case 'X'u8:
        return Outcome.Lose

    case 'Y'u8:
        return Outcome.Draw

    case 'Z'u8:
        return Outcome.Win
    }

    Swag.assert(false)
    return Outcome.Lose
}

func roundOutcome(mine: Shape, opponent: Shape)->Outcome
{
    if mine == opponent do
        return Outcome.Draw

    switch mine
    {
    case .Rock:
        return opponent == Shape.Scissors ? Outcome.Win : Outcome.Lose

    case .Paper:
        return opponent == Shape.Rock ? Outcome.Win : Outcome.Lose

    case Shape.Scissors:
        return opponent == Shape.Paper ? Outcome.Win : Outcome.Lose
    }

    Swag.assert(false)
    return Outcome.Lose
}

func chooseShape(opponent: Shape, desired: Outcome)->Shape
{
    if desired == Outcome.Draw do
        return opponent

    switch opponent
    {
    case .Rock:
        return desired == Outcome.Win ? Shape.Paper : Shape.Scissors

    case .Paper:
        return desired == Outcome.Win ? Shape.Scissors : Shape.Rock

    case Shape.Scissors:
        return desired == Outcome.Win ? Shape.Rock : Shape.Paper
    }

    Swag.assert(false)
    return Shape.Rock
}

func roundScore(mine: Shape, opponent: Shape)->u32
{
    return cast(u32) mine + cast(u32) roundOutcome(mine, opponent)
}

func storeRound(guide: *StrategyGuide, opponentToken: u8, codeToken: u8)
{
    Swag.assert(isOpponentToken(opponentToken))
    Swag.assert(isCodeToken(codeToken))
    Swag.assert(guide.count < MaxRounds)

    let index = guide.count
    guide.rounds[index] = GuideRound{opponentToken: opponentToken, codeToken: codeToken}
    guide.count         += 1
}

func parseGuide(bytes: const [..] u8)->StrategyGuide
{
    var result:        StrategyGuide
    var opponentToken: u8
    var codeToken:     u8
    var haveOpponent = false
    var haveCode     = false

    for bytes.count
    {
        let ch = bytes[Swag.index]
        if ch == ' 'u8 or ch == '\r'u8 do
            continue

        if ch == '\n'u8
        {
            if haveOpponent or haveCode
            {
                Swag.assert(haveOpponent and haveCode)
                storeRound(&result, opponentToken, codeToken)
                haveOpponent = false
                haveCode     = false
            }

            continue
        }

        if !haveOpponent
        {
            Swag.assert(isOpponentToken(ch))
            opponentToken = ch
            haveOpponent  = true
            continue
        }

        if !haveCode
        {
            Swag.assert(isCodeToken(ch))
            codeToken = ch
            haveCode  = true
            continue
        }

        Swag.assert(false)
    }

    if haveOpponent or haveCode
    {
        Swag.assert(haveOpponent and haveCode)
        storeRound(&result, opponentToken, codeToken)
    }

    return result
}

func solveClean(guide: StrategyGuide)->ScoreSummary
{
    var result: ScoreSummary

    for guide.count
    {
        let round        = guide.rounds[cast(u32) Swag.index]
        let opponent     = decodeOpponent(round.opponentToken)
        let partOneShape = decodePartOneShape(round.codeToken)
        let desired      = decodeDesiredOutcome(round.codeToken)
        let partTwoShape = chooseShape(opponent, desired)

        result.partOne += roundScore(partOneShape, opponent)
        result.partTwo += roundScore(partTwoShape, opponent)
    }

    return result
}

impl IRoundScorer for PartOneScorer
{
    mtd impl score(opponentToken: u8, codeToken: u8)->u32
    {
        let opponent = decodeOpponent(opponentToken)
        let mine     = decodePartOneShape(codeToken)
        return roundScore(mine, opponent)
    }
}

impl IRoundScorer for PartTwoScorer
{
    mtd impl score(opponentToken: u8, codeToken: u8)->u32
    {
        let opponent = decodeOpponent(opponentToken)
        let desired  = decodeDesiredOutcome(codeToken)
        let mine     = chooseShape(opponent, desired)
        return roundScore(mine, opponent)
    }
}

#[Swag.Mixin]
func declareFeatureState()
{
    var featureRoundCount: u32
    var featurePartOne:    u32
    var featurePartTwo:    u32
}

#[Swag.Macro]
func forEachGuideLine(bytes: const [..] u8, stmt: #code(opponentToken: u8, codeToken: u8))
{
    var lineOpponentToken: u8
    var lineCodeToken:     u8
    var haveOpponent = false
    var haveCode     = false

    for bytes.count
    {
        let ch = bytes[Swag.index]
        if ch == ' 'u8 or ch == '\r'u8 do
            continue

        if ch == '\n'u8
        {
            if haveOpponent or haveCode
            {
                Swag.assert(haveOpponent and haveCode)
                #inject(stmt, opponentToken = lineOpponentToken, codeToken = lineCodeToken)
                haveOpponent = false
                haveCode     = false
            }

            continue
        }

        if !haveOpponent
        {
            Swag.assert(isOpponentToken(ch))
            lineOpponentToken = ch
            haveOpponent      = true
            continue
        }

        if !haveCode
        {
            Swag.assert(isCodeToken(ch))
            lineCodeToken = ch
            haveCode      = true
            continue
        }

        Swag.assert(false)
    }

    if haveOpponent or haveCode
    {
        Swag.assert(haveOpponent and haveCode)
        #inject(stmt, opponentToken = lineOpponentToken, codeToken = lineCodeToken)
    }
}

func solveWithLanguageFeatures(bytes: const [..] u8)->ScoreSummary
{
    declareFeatureState()

    var partOneScorer: PartOneScorer
    var partTwoScorer: PartTwoScorer
    let iPartOne = cast(IRoundScorer) partOneScorer
    let iPartTwo = cast(IRoundScorer) partTwoScorer

    defer Swag.assert(featureRoundCount <= MaxRounds)

    forEachGuideLine(bytes)
    {
        featureRoundCount += 1
        featurePartOne    += iPartOne.score(opponentToken, codeToken)
        featurePartTwo    += iPartTwo.score(opponentToken, codeToken)
    }

    var result: ScoreSummary
    result.partOne = featurePartOne
    result.partTwo = featurePartTwo
    return result
}

const SampleResult:   ScoreSummary = #run solveWithLanguageFeatures(SampleInput)
const CoverageResult: ScoreSummary = #run solveWithLanguageFeatures(CoverageInput)

#assert(#sizeof(Shape) == 1)
#assert(#sizeof(Outcome) == 1)

#test
{
    let bytes    = cast(const [..] u8) SampleInput
    let guide    = parseGuide(bytes)
    let clean    = solveClean(guide)
    let features = solveWithLanguageFeatures(bytes)

    Swag.assert(guide.count == 3'u32)
    Swag.assert(clean.partOne == 15'u32)
    Swag.assert(clean.partTwo == 12'u32)
    Swag.assert(SampleResult.partOne == clean.partOne)
    Swag.assert(SampleResult.partTwo == clean.partTwo)
    Swag.assert(features.partOne == clean.partOne)
    Swag.assert(features.partTwo == clean.partTwo)
}

#test
{
    let bytes    = cast(const [..] u8) CoverageInput
    let guide    = parseGuide(bytes)
    let clean    = solveClean(guide)
    let features = solveWithLanguageFeatures(bytes)

    Swag.assert(guide.count == 9'u32)
    Swag.assert(clean.partOne == 45'u32)
    Swag.assert(clean.partTwo == 45'u32)
    Swag.assert(CoverageResult.partOne == clean.partOne)
    Swag.assert(CoverageResult.partTwo == clean.partTwo)
    Swag.assert(features.partOne == clean.partOne)
    Swag.assert(features.partTwo == clean.partTwo)
}

#test
{
    let edgeBytes    = cast(const [..] u8) EdgeInput
    let edgeGuide    = parseGuide(edgeBytes)
    let edgeClean    = solveClean(edgeGuide)
    let edgeFeatures = solveWithLanguageFeatures(edgeBytes)

    Swag.assert(edgeGuide.count == 2'u32)
    Swag.assert(edgeGuide.rounds[0].opponentToken == 'A'u8)
    Swag.assert(edgeGuide.rounds[0].codeToken == 'Z'u8)
    Swag.assert(edgeClean.partOne == 10'u32)
    Swag.assert(edgeClean.partTwo == 10'u32)
    Swag.assert(edgeFeatures.partOne == edgeClean.partOne)
    Swag.assert(edgeFeatures.partTwo == edgeClean.partTwo)

    Swag.assert(roundOutcome(.Rock, .Rock) == .Draw)
    Swag.assert(roundOutcome(.Paper, .Rock) == .Win)
    Swag.assert(roundOutcome(.Scissors, .Rock) == .Lose)
    Swag.assert(chooseShape(.Rock, .Win) == .Paper)
    Swag.assert(chooseShape(.Paper, .Lose) == .Rock)
    Swag.assert(chooseShape(.Scissors, .Draw) == .Scissors)
}
