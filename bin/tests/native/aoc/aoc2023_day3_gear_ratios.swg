#global fileprivate

// Advent of Code 2023 - Day 3: Gear Ratios
//
// Find part numbers (numbers adjacent to symbols) and gear ratios
// (products of exactly two numbers adjacent to a '*').
// Exercises: enum, impl/mtd with arrow syntax, generics, interfaces,
// macros, mixins, #run compile-time, retval, defer, foreach,
// bitwise operators, #[Swag.Complete], function overloading.

const MaxDim = 142'u32
const MaxNumbers = 1024'u32
const MaxGears = 256'u32

const SampleInput =
"""467..114..
...*......
..35..633.
......#...
617*......
.....+.58.
..592.....
......755.
...$.*....
.664.598.."""

const TinyInput =
"""12..
..*.
..45"""

const EdgeInput =
"""100
.*.
100"""

const SingleDigitInput =
"""...
.5.
.*.
.3.
..."""

// ---------------------------------------------------------------------------
// Direction enum
// ---------------------------------------------------------------------------

enum Dir: u8 { N, NE, E, SE, S, SW, W, NW }

const DirDR: [8] s32 = [-1, -1, 0, 1, 1, 1, 0, -1]
const DirDC: [8] s32 = [0, 1, 1, 1, 0, -1, -1, -1]

func dirName(d: Dir)->string
{
    #[Swag.Complete]
    switch d
    {
    case Dir.N:  return "N"
    case Dir.NE: return "NE"
    case Dir.E:  return "E"
    case Dir.SE: return "SE"
    case Dir.S:  return "S"
    case Dir.SW: return "SW"
    case Dir.W:  return "W"
    case Dir.NW: return "NW"
    }

    return "?"
}

// ---------------------------------------------------------------------------
// Character classification
// ---------------------------------------------------------------------------

func isDigit(ch: u8)->bool  => ch >= '0''u8 and ch <= '9''u8
func isDot(ch: u8)->bool    => ch == '.''u8
func isNewline(ch: u8)->bool => ch == '\n''u8 or ch == '\r''u8
func isSymbol(ch: u8)->bool  => !isDigit(ch) and !isDot(ch) and !isNewline(ch) and ch != 0
func isGear(ch: u8)->bool    => ch == '*''u8

// ---------------------------------------------------------------------------
// Grid
// ---------------------------------------------------------------------------

struct Grid
{
    cells:  [MaxDim * MaxDim] u8
    width:  u32
    height: u32
}

impl Grid
{
    mtd const at(r, c: u32)->u8   => .cells[r * MaxDim + c]
    mtd const inBounds(r, c: s32)->bool => r >= 0 and c >= 0 and cast(u32) r < .height and cast(u32) c < .width
}

func parseGrid(bytes: const [..] u8)->Grid
{
    var result: retval
    var col: u32

    for @countof(bytes)
    {
        let ch = bytes[@index]
        if isNewline(ch)
        {
            if col > 0
            {
                if result.height == 0 do
                    result.width = col
                @assert(col == result.width)
                result.height += 1
                col = 0
            }
            continue
        }

        result.cells[result.height * MaxDim + col] = ch
        col += 1
    }

    if col > 0
    {
        @assert(col == result.width)
        result.height += 1
    }

    return result
}

// ---------------------------------------------------------------------------
// NumberEntry: a parsed number with its grid span
// ---------------------------------------------------------------------------

struct NumberEntry
{
    value: u32
    row:   u32
    col0:  u32
    col1:  u32
}

struct NumberList
{
    count:   u32
    entries: [MaxNumbers] NumberEntry
}

impl NumberList
{
    mtd push(entry: NumberEntry)
    {
        @assert(.count < MaxNumbers)
        .entries[.count] = entry
        .count += 1
    }
}

// ---------------------------------------------------------------------------
// GearCandidate: a '*' with adjacency tracking
// ---------------------------------------------------------------------------

struct GearCandidate
{
    row:        u32
    col:        u32
    adjCount:   u32
    firstVal:   u32
    secondVal:  u32
}

struct GearList
{
    count:   u32
    entries: [MaxGears] GearCandidate
}

impl GearList
{
    mtd push(entry: GearCandidate)
    {
        @assert(.count < MaxGears)
        .entries[.count] = entry
        .count += 1
    }
}

// ---------------------------------------------------------------------------
// Result
// ---------------------------------------------------------------------------

struct EngineResult
{
    partNumberSum: u64
    gearRatioSum:  u64
    partCount:     u32
    gearCount:     u32
}

// ---------------------------------------------------------------------------
// Interface: abstracted adjacency checker
// ---------------------------------------------------------------------------

interface IAdjacencyChecker
{
    mtd hasAdjacentSymbol(grid: Grid, entry: NumberEntry)->bool;
}

struct DirectChecker {}

impl IAdjacencyChecker for DirectChecker
{
    mtd impl hasAdjacentSymbol(grid: Grid, entry: NumberEntry)->bool
    {
        return checkAdjacentSymbol(grid, entry)
    }
}

func checkAdjacentSymbol(grid: Grid, entry: NumberEntry)->bool
{
    let r = cast(s32) entry.row

    for c in cast(s32) entry.col0 to cast(s32) entry.col1
    {
        for 8
        {
            let nr = r + DirDR[@index]
            let nc = c + DirDC[@index]
            if grid.inBounds(nr, nc) and isSymbol(grid.at(cast(u32) nr, cast(u32) nc)) do
                return true
        }
    }

    return false
}

// ---------------------------------------------------------------------------
// Generic min/max
// ---------------------------------------------------------------------------

func(T) minOf(a, b: T)->T
{
    if a < b do
        return a
    return b
}

func(T) maxOf(a, b: T)->T
{
    if a > b do
        return a
    return b
}

// ---------------------------------------------------------------------------
// Macro: iterate all cells around a number span
// ---------------------------------------------------------------------------

#[Swag.Macro]
func forEachNeighborCell(grid: Grid, entry: NumberEntry, stmt: #code void)
{
    let rStart = maxOf's32(0, cast(s32) entry.row - 1)
    let rEnd   = minOf's32(cast(s32) grid.height - 1, cast(s32) entry.row + 1)
    let cStart = maxOf's32(0, cast(s32) entry.col0 - 1)
    let cEnd   = minOf's32(cast(s32) grid.width - 1, cast(s32) entry.col1 + 1)

    for r in rStart to rEnd
    {
        for c in cStart to cEnd
        {
            if cast(u32) r == entry.row and cast(u32) c >= entry.col0 and cast(u32) c <= entry.col1 do
                continue
            let #alias0 = cast(u32) r
            let #alias1 = cast(u32) c
            #inject(stmt)
        }
    }
}

// ---------------------------------------------------------------------------
// Mixin: declare solver state
// ---------------------------------------------------------------------------

#[Swag.Mixin]
func declareSolverState()
{
    var numbers: NumberList
    var gears:   GearList
    var result:  EngineResult
}

// ---------------------------------------------------------------------------
// Clean solve
// ---------------------------------------------------------------------------

func extractNumbers(grid: Grid)->NumberList
{
    var result: retval

    for row in grid.height
    {
        var col: u32
        while col < grid.width
        {
            let ch = grid.at(row, col)
            if isDigit(ch)
            {
                var value: u32
                let col0 = col
                while col < grid.width and isDigit(grid.at(row, col))
                {
                    value = value * 10 + cast(u32) (grid.at(row, col) - '0''u8)
                    col += 1
                }

                var entry: NumberEntry
                entry.value = value
                entry.row = row
                entry.col0 = col0
                entry.col1 = col - 1
                result.push(entry)
            }
            else
            {
                col += 1
            }
        }
    }

    return result
}

func solveClean(grid: Grid)->EngineResult
{
    var result: retval
    let numbers = extractNumbers(grid)

    // Part 1: sum part numbers
    for i in numbers.count
    {
        let entry = numbers.entries[i]
        if checkAdjacentSymbol(grid, entry)
        {
            result.partNumberSum += cast(u64) entry.value
            result.partCount += 1
        }
    }

    // Part 2: gear ratios
    for row in grid.height
    {
        for col in grid.width
        {
            if !isGear(grid.at(row, col)) do
                continue

            var adjCount: u32
            var prod: u64 = 1

            for i in numbers.count
            {
                let entry = numbers.entries[i]
                if isAdjacentToCell(entry, row, col)
                {
                    adjCount += 1
                    prod *= cast(u64) entry.value
                }
            }

            if adjCount == 2
            {
                result.gearRatioSum += prod
                result.gearCount += 1
            }
        }
    }

    return result
}

func isAdjacentToCell(entry: NumberEntry, row, col: u32)->bool
{
    let dr = cast(s32) entry.row - cast(s32) row
    if dr < -1 or dr > 1 do
        return false

    let cStart = cast(s32) entry.col0 - 1
    let cEnd   = cast(s32) entry.col1 + 1

    return cast(s32) col >= cStart and cast(s32) col <= cEnd
}

// ---------------------------------------------------------------------------
// Language-features solve: uses interface, macro, mixin, foreach
// ---------------------------------------------------------------------------

func solveWithLanguageFeatures(grid: Grid)->EngineResult
{
    declareSolverState()
    numbers = extractNumbers(grid)

    var checker: DirectChecker
    let iChecker = cast(IAdjacencyChecker) checker

    // Part 1 via interface dispatch
    foreach entry, idx in numbers.entries[0 until numbers.count]
    {
        if iChecker.hasAdjacentSymbol(grid, entry)
        {
            result.partNumberSum += cast(u64) entry.value
            result.partCount += 1
        }
    }

    // Part 2 via macro iteration
    for i in numbers.count
    {
        let entry = numbers.entries[i]

        forEachNeighborCell(|nr, nc| grid, entry)
        {
            if isGear(grid.at(nr, nc))
            {
                // Find or create gear entry
                var found = false
                for g in gears.count
                {
                    if gears.entries[g].row == nr and gears.entries[g].col == nc
                    {
                        gears.entries[g].adjCount += 1
                        gears.entries[g].secondVal = entry.value
                        found = true
                        break
                    }
                }

                if !found
                {
                    var gc: GearCandidate
                    gc.row = nr
                    gc.col = nc
                    gc.adjCount = 1
                    gc.firstVal = entry.value
                    gears.push(gc)
                }

                break
            }
        }
    }

    // Sum gear ratios
    foreach gear in gears.entries[0 until gears.count]
    {
        if gear.adjCount == 2
        {
            result.gearRatioSum += cast(u64) gear.firstVal * cast(u64) gear.secondVal
            result.gearCount += 1
        }
    }

    return result
}

// ---------------------------------------------------------------------------
// Compile-time character classification
// ---------------------------------------------------------------------------

#assert(#run isDigit('5''u8) == true)
#assert(#run isDigit('.''u8) == false)
#assert(#run isSymbol('*''u8) == true)
#assert(#run isSymbol('.''u8) == false)
#assert(#run isGear('*''u8) == true)
#assert(#run minOf's32(3, 7) == 3)
#assert(#run maxOf'u32(10, 5) == 10)

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#test
{
    let grid = parseGrid(cast(const [..] u8) SampleInput)
    @assert(grid.width == 10'u32)
    @assert(grid.height == 10'u32)
    @assert(grid.at(0, 0) == '4''u8)
    @assert(grid.at(1, 3) == '*''u8)

    let clean = solveClean(grid)
    @assert(clean.partNumberSum == 4361'u64)
    @assert(clean.gearRatioSum == 467835'u64)

    let feat = solveWithLanguageFeatures(grid)
    @assert(feat.partNumberSum == clean.partNumberSum)
    @assert(feat.gearRatioSum == clean.gearRatioSum)
    @assert(feat.partCount == clean.partCount)
    @assert(feat.gearCount == clean.gearCount)

    @assert(clean.gearCount == 2'u32)
}

#test
{
    let grid = parseGrid(cast(const [..] u8) TinyInput)
    @assert(grid.width == 4'u32)
    @assert(grid.height == 3'u32)

    let clean = solveClean(grid)
    // 12 adjacent to '*' via (0,1)→(1,2). 45 adjacent to '*' via (2,2)→(1,2).
    @assert(clean.partNumberSum == 57'u64)
    // '*' at (1,2) has exactly 2 neighbors: 12, 45 → gear ratio = 540
    @assert(clean.gearRatioSum == 540'u64)

    let feat = solveWithLanguageFeatures(grid)
    @assert(feat.partNumberSum == clean.partNumberSum)
    @assert(feat.gearRatioSum == clean.gearRatioSum)
}

#test
{
    let grid = parseGrid(cast(const [..] u8) EdgeInput)
    let clean = solveClean(grid)
    // Both 100s are adjacent to '*'
    @assert(clean.partNumberSum == 200'u64)
    // '*' has exactly 2 adjacent numbers → gear ratio = 10000
    @assert(clean.gearRatioSum == 10000'u64)

    let feat = solveWithLanguageFeatures(grid)
    @assert(feat.partNumberSum == clean.partNumberSum)
    @assert(feat.gearRatioSum == clean.gearRatioSum)
}

#test
{
    let grid = parseGrid(cast(const [..] u8) SingleDigitInput)
    let clean = solveClean(grid)
    // 5 adjacent to '*', 3 adjacent to '*'
    @assert(clean.partNumberSum == 8'u64)
    // '*' touches 5 and 3 → gear ratio = 15
    @assert(clean.gearRatioSum == 15'u64)

    let feat = solveWithLanguageFeatures(grid)
    @assert(feat.partNumberSum == clean.partNumberSum)
    @assert(feat.gearRatioSum == clean.gearRatioSum)
}

#test
{
    // Character classification coverage
    @assert(isDigit('0''u8))
    @assert(isDigit('9''u8))
    @assert(!isDigit('a''u8))
    @assert(isDot('.''u8))
    @assert(!isDot('*''u8))
    @assert(isSymbol('*''u8))
    @assert(isSymbol('#''u8))
    @assert(isSymbol('+''u8))
    @assert(isSymbol('$''u8))
    @assert(!isSymbol('.''u8))
    @assert(!isSymbol('5''u8))
    @assert(isGear('*''u8))
    @assert(!isGear('#''u8))

    // Direction name coverage
    @assert(dirName(Dir.N) == "N")
    @assert(dirName(Dir.SE) == "SE")

    // Generic min/max
    @assert(minOf's32(3, 7) == 3)
    @assert(maxOf's32(3, 7) == 7)
    @assert(minOf'u32(10, 5) == 5)
    @assert(maxOf'u32(10, 5) == 10)

    // Adjacency check
    var entry: NumberEntry
    entry.value = 35
    entry.row = 2
    entry.col0 = 2
    entry.col1 = 3
    @assert(isAdjacentToCell(entry, 1, 3))
    @assert(isAdjacentToCell(entry, 2, 1))
    @assert(!isAdjacentToCell(entry, 0, 0))
    @assert(!isAdjacentToCell(entry, 4, 4))
}
