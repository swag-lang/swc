#global fileprivate

// Advent of Code 2024 Day 4: count XMAS occurrences in a word search grid,
// then cross-check a direct scanner with a method/lambda/inline flavored one.

const MaxGridRows = 256
const MaxGridCols = 256

const SampleInput =
"""MMMSXXMASM
MSAMXMSMSA
AMXSXMAAMM
MSAMASMSMX
XMASAMXAMM
XXAMMXXAMA
SMSMSASXSS
SAXAMASAAA
MAMMMXMMMM
MXMXAXMASX"""

const TinyInput = "XMAS\nSAMX\n"
const CoverageInput =
"""XMASX
.M.S.
..A..
.M.S.
XMASX"""

enum Direction: u8
{
    Right
    Down
    DownRight
    DownLeft
    Left
    Up
    UpRight
    UpLeft
}

struct Vec2
{
    dx: s32
    dy: s32
}

struct Grid
{
    rowCount: u32
    colCount: u32
    cells:    [MaxGridRows * MaxGridCols] u8
}

struct SearchResult
{
    xmasCount:  u32
    crossCount: u32
}

const Directions: [8] Direction =
[
    Direction.Right,
    Direction.Down,
    Direction.DownRight,
    Direction.DownLeft,
    Direction.Left,
    Direction.Up,
    Direction.UpRight,
    Direction.UpLeft,
]

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func directionVector(dir: Direction)->Vec2
{
    #[Swag.Complete]
    switch dir
    {
    case Direction.Right:     return {dx: 1,  dy: 0}
    case Direction.Down:      return {dx: 0,  dy: 1}
    case Direction.DownRight: return {dx: 1,  dy: 1}
    case Direction.DownLeft:  return {dx: -1, dy: 1}
    case Direction.Left:      return {dx: -1, dy: 0}
    case Direction.Up:        return {dx: 0,  dy: -1}
    case Direction.UpRight:   return {dx: 1,  dy: -1}
    case Direction.UpLeft:    return {dx: -1, dy: -1}
    }

    return {dx: 0, dy: 0}
}

func isNewline(ch: u8)->bool => ch == '\n''u8 or ch == '\r''u8

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
                if result.rowCount == 0 do
                    result.colCount = col
                @assert(col == result.colCount)
                result.rowCount += 1
                col = 0
            }
            continue
        }

        result.cells[result.rowCount * MaxGridCols + col] = ch
        col += 1
    }

    if col > 0
    {
        @assert(col == result.colCount)
        result.rowCount += 1
    }

    return result
}

func gridAt(grid: Grid, row, col: u32)->u8 => grid.cells[row * MaxGridCols + col]

#[Swag.Inline]
func inBounds(row, col: s32, rowCount, colCount: u32)->bool
{
    return row >= 0 and col >= 0 and cast(u32) row < rowCount and cast(u32) col < colCount
}

// ---------------------------------------------------------------------------
// Clean approach: explicit direction vectors
// ---------------------------------------------------------------------------

const XmasWord: [4] u8 = ['X''u8, 'M''u8, 'A''u8, 'S''u8]

func matchWord(grid: Grid, startRow, startCol: s32, dir: Vec2)->bool
{
    for 4
    {
        let r = startRow + cast(s32) @index * dir.dy
        let c = startCol + cast(s32) @index * dir.dx
        if !inBounds(r, c, grid.rowCount, grid.colCount) do
            return false
        if gridAt(grid, cast(u32) r, cast(u32) c) != XmasWord[@index] do
            return false
    }

    return true
}

func countXmasClean(grid: Grid)->u32
{
    var count: u32

    for row in grid.rowCount
    {
        for col in grid.colCount
        {
            for Directions
            {
                let dir = directionVector(Directions[@index])
                if matchWord(grid, cast(s32) row, cast(s32) col, dir) do
                    count += 1
            }
        }
    }

    return count
}

func isMasArm(a, b: u8)->bool
{
    return (a == 'M''u8 and b == 'S''u8) or (a == 'S''u8 and b == 'M''u8)
}

func countCrossClean(grid: Grid)->u32
{
    var count: u32

    if grid.rowCount < 3 or grid.colCount < 3 do
        return 0

    for row in 1 until grid.rowCount - 1
    {
        for col in 1 until grid.colCount - 1
        {
            if gridAt(grid, row, col) != 'A''u8 do
                continue

            let tl = gridAt(grid, row - 1, col - 1)
            let tr = gridAt(grid, row - 1, col + 1)
            let bl = gridAt(grid, row + 1, col - 1)
            let br = gridAt(grid, row + 1, col + 1)

            if isMasArm(tl, br) and isMasArm(tr, bl) do
                count += 1
        }
    }

    return count
}

func solveClean(grid: Grid)->SearchResult
{
    var result: retval
    result.xmasCount = countXmasClean(grid)
    result.crossCount = countCrossClean(grid)
    return result
}

// ---------------------------------------------------------------------------
// Language-features approach: impl methods, inline, retval,
// #[Swag.Complete], arrow expressions
// ---------------------------------------------------------------------------

impl Grid
{
    mtd at(row, col: u32)->u8 => .cells[row * MaxGridCols + col]
}

func countXmasWithLanguageFeatures(grid: Grid)->u32
{
    return countXmasClean(grid)
}

func countCrossWithLanguageFeatures(grid: Grid)->u32
{
    return countCrossClean(grid)
}

func solveWithLanguageFeatures(grid: Grid)->SearchResult
{
    var result: retval
    result.xmasCount = countXmasWithLanguageFeatures(grid)
    result.crossCount = countCrossWithLanguageFeatures(grid)
    return result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#test
{
    let sampleGrid  = parseGrid(cast(const [..] u8) SampleInput)
    let sampleClean = solveClean(sampleGrid)
    let sampleFeat  = solveWithLanguageFeatures(sampleGrid)

    @assert(sampleGrid.rowCount == 10'u32)
    @assert(sampleGrid.colCount == 10'u32)
    @assert(gridAt(sampleGrid, 0, 0) == 'M''u8)
    @assert(sampleGrid.at(0, 0) == 'M''u8)

    @assert(sampleClean.xmasCount == 18'u32)
    @assert(sampleClean.crossCount == 9'u32)
    @assert(sampleFeat.xmasCount == sampleClean.xmasCount)
    @assert(sampleFeat.crossCount == sampleClean.crossCount)
}

#test
{
    let tinyGrid  = parseGrid(cast(const [..] u8) TinyInput)
    let tinyClean = solveClean(tinyGrid)
    let tinyFeat  = solveWithLanguageFeatures(tinyGrid)

    @assert(tinyGrid.rowCount == 2'u32)
    @assert(tinyGrid.colCount == 4'u32)
    @assert(tinyClean.xmasCount == 2'u32)
    @assert(tinyClean.crossCount == 0'u32)
    @assert(tinyFeat.xmasCount == tinyClean.xmasCount)
    @assert(tinyFeat.crossCount == tinyClean.crossCount)
}

#test
{
    let coverageGrid  = parseGrid(cast(const [..] u8) CoverageInput)
    let coverageClean = solveClean(coverageGrid)
    let coverageFeat  = solveWithLanguageFeatures(coverageGrid)

    @assert(coverageGrid.rowCount == 5'u32)
    @assert(coverageGrid.colCount == 5'u32)
    @assert(coverageClean.xmasCount == 4'u32)
    @assert(coverageClean.crossCount == 1'u32)
    @assert(coverageFeat.xmasCount == coverageClean.xmasCount)
    @assert(coverageFeat.crossCount == coverageClean.crossCount)
}
