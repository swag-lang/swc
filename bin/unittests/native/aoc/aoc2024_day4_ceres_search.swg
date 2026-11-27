#global private

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

const TinyInput     = "XMAS\nSAMX\n"
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
    Direction.UpLeft
    ]

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func directionVector(dir: Direction)->Vec2
{
    switch #complete dir
    {
    case Direction.Right:     return {dx: 1, dy: 0}
    case Direction.Down:      return {dx: 0, dy: 1}
    case Direction.DownRight: return {dx: 1, dy: 1}
    case Direction.DownLeft:  return {dx: -1, dy: 1}
    case Direction.Left:      return {dx: -1, dy: 0}
    case Direction.Up:        return {dx: 0, dy: -1}
    case Direction.UpRight:   return {dx: 1, dy: -1}
    case Direction.UpLeft:    return {dx: -1, dy: -1}
    }
}

func isNewline(ch: u8)->bool => ch == '\n'_u8 or ch == '\r'_u8

func parseGrid(bytes: const [..] u8)->Grid
{
    var result: #returntype

    var col: u32
    for index in bytes.count
    {
        let ch = bytes[index]
        if isNewline(ch)
        {
            if col > 0
            {
                if result.rowCount == 0
                {
                    result.colCount = col
                }
                Swag.assert(col == result.colCount)
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
        Swag.assert(col == result.colCount)
        result.rowCount += 1
    }

    return result
}

func gridAt(grid: Grid, row, col: u32)->u8 => grid.cells[row * MaxGridCols + col]

#[Swag.Inline]
func inBounds(row, col: s32, rowCount, colCount: u32)->bool
{
    return row >= 0 and col >= 0 and cast(u32, row) < rowCount and cast(u32, col) < colCount
}

// ---------------------------------------------------------------------------
// Clean approach: explicit direction vectors
// ---------------------------------------------------------------------------

const XmasWord: [4] u8 = ['X'_u8, 'M'_u8, 'A'_u8, 'S'_u8]

func matchWord(grid: Grid, startRow, startCol: s32, dir: Vec2)->bool
{
    for index in 4
    {
        let r = startRow + cast(s32, index) * dir.dy
        let c = startCol + cast(s32, index) * dir.dx
        if not inBounds(r, c, grid.rowCount, grid.colCount)
        {
            return false
        }
        if gridAt(grid, cast(u32, r), cast(u32, c)) != XmasWord[index]
        {
            return false
        }
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
            for index in Directions.count
            {
                let dir = directionVector(Directions[index])
                if matchWord(grid, cast(s32, row), cast(s32, col), dir)
                {
                    count += 1
                }
            }
        }
    }

    return count
}

func isMasArm(a, b: u8)->bool
{
    return (a == 'M'_u8 and b == 'S'_u8) or (a == 'S'_u8 and b == 'M'_u8)
}

func countCrossClean(grid: Grid)->u32
{
    var count: u32

    if grid.rowCount < 3 or grid.colCount < 3
    {
        return 0
    }

    for row in 1 until grid.rowCount - 1
    {
        for col in 1 until grid.colCount - 1
        {
            if gridAt(grid, row, col) != 'A'_u8
            {
                continue
            }

            let tl = gridAt(grid, row - 1, col - 1)
            let tr = gridAt(grid, row - 1, col + 1)
            let bl = gridAt(grid, row + 1, col - 1)
            let br = gridAt(grid, row + 1, col + 1)

            if isMasArm(tl, br) and isMasArm(tr, bl)
            {
                count += 1
            }
        }
    }

    return count
}

func solveClean(grid: Grid)->SearchResult
{
    var result: #returntype
    result.xmasCount  = countXmasClean(grid)
    result.crossCount = countCrossClean(grid)
    return result
}

// ---------------------------------------------------------------------------
// Language-features approach: impl methods, inline, #returntype,
// 'switch #complete', arrow expressions
// ---------------------------------------------------------------------------

impl Grid
{
    mtd const at(row, col: u32)->u8 => .cells[row * MaxGridCols + col]
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
    var result: #returntype
    result.xmasCount  = countXmasWithLanguageFeatures(grid)
    result.crossCount = countCrossWithLanguageFeatures(grid)
    return result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#test
{
    let sampleGrid  = parseGrid(cast(const [..] u8, SampleInput))
    let sampleClean = solveClean(sampleGrid)
    let sampleFeat  = solveWithLanguageFeatures(sampleGrid)

    Swag.require(sampleGrid.rowCount == 10_u32)
    Swag.require(sampleGrid.colCount == 10_u32)
    Swag.require(gridAt(sampleGrid, 0, 0) == 'M'_u8)
    Swag.require(sampleGrid.at(0, 0) == 'M'_u8)

    Swag.require(sampleClean.xmasCount == 18_u32)
    Swag.require(sampleClean.crossCount == 9_u32)
    Swag.require(sampleFeat.xmasCount == sampleClean.xmasCount)
    Swag.require(sampleFeat.crossCount == sampleClean.crossCount)
}

#test
{
    let tinyGrid  = parseGrid(cast(const [..] u8, TinyInput))
    let tinyClean = solveClean(tinyGrid)
    let tinyFeat  = solveWithLanguageFeatures(tinyGrid)

    Swag.require(tinyGrid.rowCount == 2_u32)
    Swag.require(tinyGrid.colCount == 4_u32)
    Swag.require(tinyClean.xmasCount == 2_u32)
    Swag.require(tinyClean.crossCount == 0_u32)
    Swag.require(tinyFeat.xmasCount == tinyClean.xmasCount)
    Swag.require(tinyFeat.crossCount == tinyClean.crossCount)
}

#test
{
    let coverageGrid  = parseGrid(cast(const [..] u8, CoverageInput))
    let coverageClean = solveClean(coverageGrid)
    let coverageFeat  = solveWithLanguageFeatures(coverageGrid)

    Swag.require(coverageGrid.rowCount == 5_u32)
    Swag.require(coverageGrid.colCount == 5_u32)
    Swag.require(coverageClean.xmasCount == 4_u32)
    Swag.require(coverageClean.crossCount == 1_u32)
    Swag.require(coverageFeat.xmasCount == coverageClean.xmasCount)
    Swag.require(coverageFeat.crossCount == coverageClean.crossCount)
}
