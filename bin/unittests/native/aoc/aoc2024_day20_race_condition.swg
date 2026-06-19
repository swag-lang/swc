#global fileprivate

// Advent of Code 2024 Day 20: find shortcuts (cheats) in a racetrack maze.
// Part 1: cheats up to 2 picoseconds, count those saving >= threshold.
// Part 2: cheats up to 20 picoseconds, count those saving >= threshold.
// Exercises: @abs on s32, #[Swag.Inline] func with retval returning struct,
// nested inline mtd (isOpen→cell→idx), signed cast arithmetic, defer cleanup.

const SampleInput =
"""###############
#...#...#.....#
#.#.#.#.#.###.#
#S#...#.#.#...#
#######.#.#.###
#######.#.#...#
#######.#.###.#
###..E#...#...#
###.#######.###
#...###...#...#
#.#####.#.###.#
#.#...#.#.#...#
#.#.#.#.#.#.###
#...#...#...###
###############"""

// ---------------------------------------------------------------------------
// Grid
// ---------------------------------------------------------------------------

const MaxDim   = 150'u32
const MaxCells = MaxDim * MaxDim
const Unvisited = 0xFFFFFFFF'u32

struct Grid
{
    cells:  [*] u8
    dist:   [*] u32      // distance from S along the single path
    w:      u32
    h:      u32
    sr:     u32
    sc:     u32
    er:     u32
    ec:     u32
    pathLen: u32          // total path length (S to E)
}

func gridInit() -> Grid
{
    var g: Grid
    g.cells = cast([*] u8)  @alloc(cast(u64) MaxCells)
    g.dist  = cast([*] u32) @alloc(cast(u64) MaxCells * #sizeof(u32))
    for MaxCells
    {
        g.cells[@index] = 0
        g.dist[@index]  = Unvisited
    }
    return g
}

func gridFree(g: *Grid)
{
    if g.cells do @free(g.cells)
    if g.dist  do @free(g.dist)
}

impl Grid
{
    #[Swag.Inline]
    mtd idx(r: u32, c: u32) -> u32 { return r * MaxDim + c }

    #[Swag.Inline]
    mtd cell(r: u32, c: u32) -> u8 { return me.cells[me.idx(r, c)] }

    #[Swag.Inline]
    mtd isOpen(r: u32, c: u32) -> bool { return me.cell(r, c) != '#' }

    #[Swag.Inline]
    mtd distAt(r: u32, c: u32) -> u32 { return me.dist[me.idx(r, c)] }

    mtd setDist(r: u32, c: u32, d: u32) { me.dist[me.idx(r, c)] = d }

    #[Swag.Inline]
    mtd inBounds(r: s32, c: s32) -> bool
    {
        if r < 0 or c < 0 do return false
        return cast(u32) r < me.h and cast(u32) c < me.w
    }
}

// ---------------------------------------------------------------------------
// Pos: small struct returned from inline method
// ---------------------------------------------------------------------------

struct Pos
{
    r: u32
    c: u32
}

// Inline function returning a struct via retval
#[Swag.Inline]
func makePos(r: u32, c: u32) -> Pos
{
    var result: retval
    result.r = r
    result.c = c
    return result
}

// Manhattan distance using @abs and signed casts
#[Swag.Inline]
func manhattan(a: Pos, b: Pos) -> u32
{
    let dr = cast(s32) a.r - cast(s32) b.r
    let dc = cast(s32) a.c - cast(s32) b.c
    return cast(u32) @abs(dr) + cast(u32) @abs(dc)
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

func parseGrid(text: string) -> Grid
{
    var g = gridInit()
    let bytes = cast(const [..] u8) text
    var row: u32
    var col: u32

    for @countof(bytes)
    {
        let ch = bytes[@index]
        if ch == '\n' or ch == '\r'
        {
            if col > 0
            {
                if g.h == 0 do g.w = col
                g.h += 1
                row += 1
                col = 0
            }
            continue
        }

        g.cells[row * MaxDim + col] = ch
        if ch == 'S' { g.sr = row; g.sc = col }
        if ch == 'E' { g.er = row; g.ec = col }
        col += 1
    }

    if col > 0
    {
        g.w = @max(g.w, col)
        g.h += 1
    }

    return g
}

// ---------------------------------------------------------------------------
// Trace the single path from S to E
// ---------------------------------------------------------------------------

const DR: [4] s32 = [0, 1, 0, -1]
const DC: [4] s32 = [1, 0, -1, 0]

func tracePath(g: *Grid)
{
    g.setDist(g.sr, g.sc, 0)
    var cr = g.sr
    var cc = g.sc
    var d: u32 = 0

    for MaxCells
    {
        if cr == g.er and cc == g.ec do break
        var moved = false
        for dir in 4
        {
            let nr = cast(s32) cr + DR[dir]
            let nc = cast(s32) cc + DC[dir]
            if !g.inBounds(nr, nc) do continue
            let ur = cast(u32) nr
            let uc = cast(u32) nc
            if !g.isOpen(ur, uc) do continue
            if g.distAt(ur, uc) != Unvisited do continue
            d += 1
            g.setDist(ur, uc, d)
            cr = ur
            cc = uc
            moved = true
            break
        }
        if !moved do break
    }

    g.pathLen = d
}

// ---------------------------------------------------------------------------
// Count cheats: for each pair of path cells within cheat distance,
// check if the shortcut saves enough time.
// ---------------------------------------------------------------------------

func countCheats(g: *Grid, maxCheat: u32, minSaving: u32) -> u64
{
    var count: u64

    // Collect path cells into array for efficient pairwise iteration
    let pathSize = g.pathLen + 1
    let pathBuf = cast([*] Pos) @alloc(cast(u64) pathSize * #sizeof(Pos))
    defer @free(pathBuf)

    // Fill path buffer in distance order
    for r in g.h
    {
        for c in g.w
        {
            let d = g.distAt(r, c)
            if d != Unvisited and d < pathSize
            {
                pathBuf[d] = makePos(r, c)
            }
        }
    }

    // For each pair of path cells
    for i in pathSize
    {
        let pi = pathBuf[i]
        // Only check cells further along the path that could save time
        let minJ = i + minSaving
        if minJ >= pathSize do continue

        for j in minJ until pathSize
        {
            let pj = pathBuf[j]
            let md = manhattan(pi, pj)
            if md > maxCheat do continue

            // Saving = path distance difference - manhattan distance
            let pathDist = j - i
            if pathDist > md
            {
                let saving = pathDist - md
                if saving >= minSaving
                {
                    count += 1
                }
            }
        }
    }

    return count
}

// ---------------------------------------------------------------------------
// Solver
// ---------------------------------------------------------------------------

struct SolveResult
{
    part1: u64
    part2: u64
}

func solve(text: string, minSaving: u32) -> SolveResult
{
    var g = parseGrid(text)
    defer gridFree(&g)
    tracePath(&g)

    var result: SolveResult
    result.part1 = countCheats(&g, 2, minSaving)
    result.part2 = countCheats(&g, 20, minSaving)
    return result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// Parse grid
#test
{
    var g = parseGrid(SampleInput)
    defer gridFree(&g)
    @assert(g.w == 15'u32)
    @assert(g.h == 15'u32)
    @assert(g.sr == 3'u32)
    @assert(g.sc == 1'u32)
    @assert(g.er == 7'u32)
    @assert(g.ec == 5'u32)
}

// Grid inline methods: nested inline (isOpen → cell → idx)
#test
{
    var g = parseGrid(SampleInput)
    defer gridFree(&g)
    @assert(!g.isOpen(0, 0))      // wall
    @assert(g.isOpen(1, 1))       // open
    @assert(g.cell(0, 0) == '#')
    @assert(g.cell(3, 1) == 'S')
}

// Pos.make inline returning struct
#test
{
    let p = makePos(3, 7)
    @assert(p.r == 3'u32)
    @assert(p.c == 7'u32)
}

// Manhattan distance with @abs on s32
#test
{
    let a = makePos(1, 5)
    let b = makePos(4, 2)
    @assert(manhattan(a, b) == 6'u32)

    // Same point
    @assert(manhattan(a, a) == 0'u32)

    // Reversed order
    @assert(manhattan(b, a) == 6'u32)
}

// Trace path
#test
{
    var g = parseGrid(SampleInput)
    defer gridFree(&g)
    tracePath(&g)
    @assert(g.pathLen == 84'u32)
    @assert(g.distAt(g.sr, g.sc) == 0'u32)
    @assert(g.distAt(g.er, g.ec) == 84'u32)
}

// Part 1: cheats of length 2, saving >= 2 → 44
#test
{
    let result = solve(SampleInput, 2)
    @assert(result.part1 == 44'u64)
}

// Part 2: cheats of length 20, saving >= 50 → 285
#test
{
    let result = solve(SampleInput, 50)
    @assert(result.part2 == 285'u64)
}

// Edge: single-cell path (S == E)
#test
{
    var g = gridInit()
    defer gridFree(&g)
    g.w = 3; g.h = 3
    // ###
    // #S#   (S is also E)
    // ###
    g.cells[0 * MaxDim + 0] = '#'; g.cells[0 * MaxDim + 1] = '#'; g.cells[0 * MaxDim + 2] = '#'
    g.cells[1 * MaxDim + 0] = '#'; g.cells[1 * MaxDim + 1] = 'S'; g.cells[1 * MaxDim + 2] = '#'
    g.cells[2 * MaxDim + 0] = '#'; g.cells[2 * MaxDim + 1] = '#'; g.cells[2 * MaxDim + 2] = '#'
    g.sr = 1; g.sc = 1; g.er = 1; g.ec = 1
    tracePath(&g)
    @assert(g.pathLen == 0'u32)
}

// Manhattan distance edge: large coordinates
#test
{
    let a = makePos(0, 0)
    let b = makePos(100, 100)
    @assert(manhattan(a, b) == 200'u32)
}

// inBounds inline with signed args
#test
{
    var g = parseGrid(SampleInput)
    defer gridFree(&g)
    @assert(g.inBounds(0, 0))
    var neg: s32 = -1
    @assert(!g.inBounds(neg, 0))
    @assert(!g.inBounds(0, neg))
    @assert(g.inBounds(cast(s32) g.h - 1, cast(s32) g.w - 1))
    @assert(!g.inBounds(cast(s32) g.h, 0))
}
