#global fileprivate

// Advent of Code 2024 Day 10: find hiking trails on a topographic map where
// each step increases height by exactly 1 from 0 to 9.
// Part 1 (score): count distinct 9-height cells reachable from each trailhead.
// Part 2 (rating): count total distinct paths from each trailhead to any 9.
// Exercises: nested functions, #if/#else, const from func, @min/@max,
// 0 until N range, #[Swag.Discardable], tuple-like struct returns.

const MaxDim = 64'u32
const NumHeights = 10'u32

const SampleInput =
"""89010123
78121874
87430965
96549874
45678903
32019012
01329801
10456732"""

const TinyInput =
"""0123
1234
8765
9876"""

const SingleInput = "9"

// ---------------------------------------------------------------------------
// Compile-time configuration
// ---------------------------------------------------------------------------

const TrailStart: u8 = 0
const TrailEnd:   u8 = 9

#if TrailEnd > TrailStart
{
    const TrailLength = TrailEnd - TrailStart
}
#else
{
    const TrailLength = 0'u8
}

#assert(TrailLength == 9)

// ---------------------------------------------------------------------------
// Grid parsing
// ---------------------------------------------------------------------------

struct Grid
{
    cells:  [MaxDim * MaxDim] u8
    width:  u32
    height: u32
}

const Directions: [4] [2] s32 = [[-1, 0], [1, 0], [0, -1], [0, 1]]

func countDirections()->u32
{
    return 4
}

const NumDirections = countDirections()
#assert(NumDirections == 4)

func parseGrid(text: string)->Grid
{
    let bytes = cast(const [..] u8) text
    var result: Grid

    var col: u32
    for @countof(bytes)
    {
        let ch = bytes[@index]
        if ch == '\n' or ch == '\r'
        {
            if col > 0
            {
                if result.height == 0 do
                    result.width = col
                result.height += 1
                col = 0
            }
            continue
        }

        result.cells[result.height * MaxDim + col] = ch - '0'
        col += 1
    }

    if col > 0
    {
        result.width = @max(result.width, col)
        result.height += 1
    }

    return result
}

#[Swag.Inline]
func cellAt(grid: const &Grid, row, col: u32)->u8
{
    @assert(row < grid.height and col < grid.width)
    return grid.cells[row * MaxDim + col]
}

// ---------------------------------------------------------------------------
// Trail finding: score (distinct 9s) and rating (distinct paths)
// ---------------------------------------------------------------------------

struct TrailResult
{
    score:  u32
    rating: u32
}

#[Swag.Discardable]
func addTrailResult(a, b: TrailResult)->TrailResult
{
    return {score: a.score + b.score, rating: a.rating + b.rating}
}

// Nested function: DFS from a cell, returns number of distinct paths to any 9.
// scoreOut is incremented for each newly-discovered 9-cell.
func dfs(g: const &Grid, row, col: u32, vis: [..] bool, scoreOut: *u32)->u32
{
    let h = cellAt(g, row, col)
    if h == TrailEnd
    {
        let idx = row * MaxDim + col
        if !vis[idx]
        {
            vis[idx] = true
            dref scoreOut += 1
        }
        return 1
    }

    var paths: u32
    let nextH = h + 1
    for dirIdx in 0 until NumDirections
    {
        let dr = Directions[dirIdx][0]
        let dc = Directions[dirIdx][1]
        let nr = cast(s32) row + dr
        let nc = cast(s32) col + dc

        if nr < 0 or nc < 0 or cast(u32) nr >= g.height or cast(u32) nc >= g.width do
            continue
        if cellAt(g, cast(u32) nr, cast(u32) nc) != nextH do
            continue

        paths += dfs(g, cast(u32) nr, cast(u32) nc, vis, scoreOut)
    }

    return paths
}

func findTrails(grid: const &Grid)->TrailResult
{
    var visited: [MaxDim * MaxDim] bool
    var totalScore: u32
    var totalRating: u32

    for row in grid.height
    {
        for col in grid.width
        {
            if cellAt(grid, row, col) != TrailStart do
                continue

            // Clear visited for this trailhead
            for grid.height
            {
                let r = cast(u32) @index
                for grid.width
                {
                    let c = cast(u32) @index
                    visited[r * MaxDim + c] = false
                }
            }

            let rating = dfs(grid, row, col, visited, &totalScore)
            totalRating += rating
        }
    }

    return {score: totalScore, rating: totalRating}
}

// ---------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------

struct HikingReport
{
    width:       u32
    height:      u32
    trailheads:  u32
    totalScore:  u32
    totalRating: u32
}

func analyzeTrails(text: string)->HikingReport
{
    var grid = parseGrid(text)

    var result: HikingReport
    result.width = grid.width
    result.height = grid.height

    for row in grid.height
    {
        for col in grid.width
        {
            if cellAt(&grid, row, col) == 0 do
                result.trailheads += 1
        }
    }

    let trails = findTrails(&grid)
    result.totalScore = trails.score
    result.totalRating = trails.rating

    return result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#test
{
    let sample = analyzeTrails(SampleInput)

    @assert(sample.width == 8'u32)
    @assert(sample.height == 8'u32)
    @assert(sample.trailheads == 9'u32)
    @assert(sample.totalScore == 36'u32)
    @assert(sample.totalRating == 81'u32)
}

#test
{
    let tiny = analyzeTrails(TinyInput)

    @assert(tiny.width == 4'u32)
    @assert(tiny.height == 4'u32)
    @assert(tiny.trailheads == 1'u32)
    @assert(tiny.totalScore == 1'u32)
    @assert(tiny.totalRating == 16'u32)
}

#test
{
    let single = analyzeTrails(SingleInput)

    @assert(single.width == 1'u32)
    @assert(single.height == 1'u32)
    @assert(single.trailheads == 0'u32)
    @assert(single.totalScore == 0'u32)
    @assert(single.totalRating == 0'u32)
}

#test
{
    @assert(NumDirections == 4'u32)
    let a: TrailResult = {score: 10, rating: 20}
    let b: TrailResult = {score: 5, rating: 15}
    let c = addTrailResult(a, b)
    @assert(c.score == 15'u32)
    @assert(c.rating == 35'u32)
}
