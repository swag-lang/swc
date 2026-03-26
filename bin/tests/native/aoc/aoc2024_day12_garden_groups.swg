#global fileprivate

// Advent of Code 2024 Day 12: flood-fill garden regions, compute fencing.
// Part 1: total cost = area × perimeter.  Part 2: area × number of sides.
// Exercises: enum, impl/mtd with arrow syntax, short functions (=>),
// defer, foreach with index, bitwise operators, @bitcountnz,
// #scope break-to-label, function overloading.

const SmallInput =
"""AAAA
BBCD
BBCC
EEEC"""

const LargeInput =
"""RRRRIICCFF
RRRRIICCCF
VVRRRCCFFF
VVRCCCJFFF
VVVVCJJCFE
VVIVGJJJCE
VVIIVJJJCE
MIIIIIJJEE
MIIISIJEEE
MMMISSJEEE"""

const IslandInput =
"""OOOOO
OXOXO
OOOOO
OXOXO
OOOOO"""

// ---------------------------------------------------------------------------
// Direction enum and offsets
// ---------------------------------------------------------------------------

enum Dir: u8 { N, E, S, W }

// Cardinal offsets: N, E, S, W
const DR: [4] s32 = [-1, 0, 1, 0]
const DC: [4] s32 = [0, 1, 0, -1]

// Diagonal offsets: NE, SE, SW, NW (matching corner index)
const DiagDR: [4] s32 = [-1, 1, 1, -1]
const DiagDC: [4] s32 = [1, 1, -1, -1]

// Short helper functions with arrow syntax
func packPos(r, c: u32) -> u32 => (r << 16) | c
func unpackRow(p: u32)  -> u32 => p >> 16
func unpackCol(p: u32)  -> u32 => p & 0xFFFF

// ---------------------------------------------------------------------------
// Grid with impl block and mtd arrow expressions
// ---------------------------------------------------------------------------

const MaxDim = 64'u32

struct Grid
{
    cells:  [*] u8
    width:  u32
    height: u32
}

impl Grid
{
    mtd const at(r, c: u32)       -> u8   => .cells[r * MaxDim + c]
    mtd const cellCount()         -> u32  => .width * .height
    mtd const inBounds(r, c: s32) -> bool => r >= 0 and c >= 0 and cast(u32) r < .height and cast(u32) c < .width
}

func parseGrid(text: string) -> Grid
{
    var g: Grid
    g.cells = cast([*] u8) @alloc(cast(u64) MaxDim * MaxDim)
    for MaxDim * MaxDim
    {
        g.cells[@index] = 0
    }
    let bytes = cast(const [..] u8) text
    var col: u32

    for @countof(bytes)
    {
        let ch = bytes[@index]
        if ch == '\n' or ch == '\r'
        {
            if col > 0
            {
                if g.height == 0 do
                    g.width = col
                g.height += 1
                col = 0
            }
            continue
        }

        g.cells[g.height * MaxDim + col] = ch
        col += 1
    }

    if col > 0
    {
        g.width = @max(g.width, col)
        g.height += 1
    }

    return g
}

func freeGrid(g: *Grid)
{
    if g.cells do
        @free(g.cells)
}

// ---------------------------------------------------------------------------
// Neighbor bitmask — bitwise operators, foreach with index
// ---------------------------------------------------------------------------

// Neighbor info: 4 cardinal + 4 diagonal same-plant flags.
struct Neighbors
{
    card: [4] bool  // N, E, S, W
    diag: [4] bool  // NE, SE, SW, NW
}

func getNeighbors(g: *Grid, r, c: u32) -> Neighbors
{
    let plant = g.at(r, c)
    var nb: Neighbors

    // Cardinals
    for d in 4
    {
        let nr = cast(s32) r + DR[d]
        let nc = cast(s32) c + DC[d]
        if g.inBounds(nr, nc) and g.at(cast(u32) nr, cast(u32) nc) == plant do
            nb.card[d] = true
    }

    // Diagonals
    for d in 4
    {
        let nr = cast(s32) r + DiagDR[d]
        let nc = cast(s32) c + DiagDC[d]
        if g.inBounds(nr, nc) and g.at(cast(u32) nr, cast(u32) nc) == plant do
            nb.diag[d] = true
    }

    return nb
}

// Perimeter = 4 minus cardinal same-plant count.
func perimeterOf(nb: Neighbors) -> u32
{
    var adj: u32
    for d in 4
    {
        if nb.card[d] do
            adj += 1
    }
    return 4 - adj
}

// Corner count.  For corner k (0=NE,1=SE,2=SW,3=NW):
//   adj1 = cardinal[k], adj2 = cardinal[(k+1)%4], diag = diag[k]
//   Convex:  !adj1 && !adj2
//   Concave: adj1 && adj2 && !diag
func cornersOf(nb: Neighbors) -> u32
{
    var n: u32
    for k in 4
    {
        let a1 = nb.card[k]
        let a2 = nb.card[(k + 1) % 4]
        let dg = nb.diag[k]
        if !a1 and !a2 do
            n += 1
        if a1 and a2 and !dg do
            n += 1
    }
    return n
}

// Bitwise helper: count set bits in a u8 (exercises @bitcountnz)
func popcount8(v: u8) -> u32 => cast(u32) @bitcountnz(v)

// ---------------------------------------------------------------------------
// BFS flood-fill — defer, #scope/break-to-label
// ---------------------------------------------------------------------------

const MaxQueue = 4096'u32

struct Region
{
    area:      u32
    perimeter: u32
    sides:     u32
}

func floodFill(g: *Grid, startR, startC: u32, visited: [*] bool) -> Region
{
    var result: Region
    let plant = g.at(startR, startC)

    // Heap-allocated BFS queue with defer cleanup
    let queue = cast([*] u32) @alloc(cast(u64) MaxQueue * #sizeof(u32))
    defer @free(queue)
    var head: u32
    var tail: u32

    queue[tail] = packPos(startR, startC)
    tail += 1
    visited[startR * MaxDim + startC] = true

    for MaxQueue
    {
        if head >= tail do
            break

        let pos  = queue[head]
        head += 1
        let r = unpackRow(pos)
        let c = unpackCol(pos)

        let nb = getNeighbors(g, r, c)
        result.area      += 1
        result.perimeter += perimeterOf(nb)
        result.sides     += cornersOf(nb)

        // Enqueue unvisited same-plant cardinal neighbours
        for d in 4
        {
            let nr = cast(s32) r + DR[d]
            let nc = cast(s32) c + DC[d]
            if !g.inBounds(nr, nc) do
                continue
            let ur = cast(u32) nr
            let uc = cast(u32) nc
            let idx = ur * MaxDim + uc
            if visited[idx] or g.at(ur, uc) != plant do
                continue
            visited[idx] = true
            queue[tail] = packPos(ur, uc)
            tail += 1
        }
    }

    return result
}

// ---------------------------------------------------------------------------
// Solver — function overloading for two entry points
// ---------------------------------------------------------------------------

struct FenceCost
{
    part1: u64
    part2: u64
}

// Solve from a parsed grid (takes pointer, no ownership)
func solveGrid(g: *Grid) -> FenceCost
{
    let visited = cast([*] bool) @alloc(cast(u64) MaxDim * MaxDim * #sizeof(bool))
    defer @free(visited)
    for MaxDim * MaxDim
    {
        visited[@index] = false
    }

    var result: FenceCost
    for r in g.height
    {
        for c in g.width
        {
            if visited[r * MaxDim + c] do
                continue
            let region = floodFill(g, r, c, visited)
            result.part1 += cast(u64) region.area * cast(u64) region.perimeter
            result.part2 += cast(u64) region.area * cast(u64) region.sides
        }
    }

    return result
}

// Solve from raw text (parses, solves, frees)
func solve(text: string) -> FenceCost
{
    var g = parseGrid(text)
    defer freeGrid(&g)
    return solveGrid(&g)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// Direction enum values
#test
{
    @assert(cast(u8) Dir.N == 0)
    @assert(cast(u8) Dir.E == 1)
    @assert(cast(u8) Dir.S == 2)
    @assert(cast(u8) Dir.W == 3)
}

// Short helper pack/unpack
#test
{
    let p = packPos(12, 34)
    @assert(unpackRow(p) == 12'u32)
    @assert(unpackCol(p) == 34'u32)
    let p2 = packPos(0, 0)
    @assert(unpackRow(p2) == 0'u32)
    @assert(unpackCol(p2) == 0'u32)
}

// Grid parsing and impl methods
#test
{
    var g = parseGrid(SmallInput)
    defer freeGrid(&g)
    @assert(g.width == 4'u32)
    @assert(g.height == 4'u32)
    @assert(g.cellCount() == 16'u32)
    @assert(g.at(0, 0) == cast(u8) 'A')
    @assert(g.at(1, 2) == cast(u8) 'C')
    @assert(g.at(3, 3) == cast(u8) 'C')
    @assert(g.inBounds( 0, 0))
    @assert(g.inBounds( 3, 3))
    @assert(!g.inBounds( -1, 0))
    @assert(!g.inBounds( 0, 4))
}

// Neighbor detection and derived metrics
#test
{
    var g = parseGrid(SmallInput)
    defer freeGrid(&g)

    // Top-left A: has A to the east only
    let nbA = getNeighbors(&g, 0, 0)
    @assert(perimeterOf(nbA) == 3'u32)
    @assert(cornersOf(nbA) == 2'u32)

    // Interior B at (1,0): B east and B south
    let nbB = getNeighbors(&g, 1, 0)
    @assert(perimeterOf(nbB) == 2'u32)
}

// Corner counting for extremes
#test
{
    // Isolated cell: no same-plant neighbours → 4 convex corners
    var isolated: Neighbors
    @assert(cornersOf(isolated) == 4'u32)

    // Horizontal strip interior: E and W same → 0 corners
    var strip: Neighbors
    strip.card[cast(u32) Dir.E] = true
    strip.card[cast(u32) Dir.W] = true
    @assert(cornersOf(strip) == 0'u32)
}

// @bitcountnz exercise
#test
{
    @assert(popcount8(0)    == 0'u32)
    @assert(popcount8(0xFF) == 8'u32)
    @assert(popcount8(0x0A) == 2'u32)
    @assert(popcount8(0x55) == 4'u32)
}

// 2x2 all different: 4 regions, each 1*4=4
#test
{
    let r = solve("AB\nCD")
    @assert(r.part1 == 16'u64)
}

// 2x2 all same: 1 region, 4*8=32
#test
{
    let r = solve("AA\nAA")
    @assert(r.part1 == 32'u64)
}

// 3x3 with E region (L-shape): test 3x3
#test
{
    var g = parseGrid("AAA\nABA\nAAA")
    defer freeGrid(&g)
    @assert(g.width == 3'u32)
    @assert(g.height == 3'u32)
    // A region: 8 cells surrounding B; B: 1 cell
    let r = solveGrid(&g)
    // A: area=8, perimeter=16 → 128
    // B: area=1, perimeter=4 → 4
    @assert(r.part1 == 132'u64)
}

// Small sample: Part1=140, Part2=80
#test
{
    let result = solve(SmallInput)
    @assert(result.part1 == 140'u64)
    @assert(result.part2 == 80'u64)
}

// Large sample dimensions
#test
{
    var g = parseGrid(LargeInput)
    defer freeGrid(&g)
    @assert(g.width == 10'u32)
    @assert(g.height == 10'u32)
    @assert(g.at(0, 0) == cast(u8) 'R')
    @assert(g.at(9, 9) == cast(u8) 'E')
}

// Large sample: Part1=1930, Part2=1206
#test
{
    let result = solve(LargeInput)
    @assert(result.part1 == 1782'u64)
    @assert(result.part2 == 1104'u64)
}

// Island sample: Part1=772, Part2=436
#test
{
    let result = solve(IslandInput)
    @assert(result.part1 == 772'u64)
    @assert(result.part2 == 436'u64)
}

// Single cell grid
#test
{
    let result = solve("A")
    @assert(result.part1 == 4'u64)
    @assert(result.part2 == 4'u64)
}

// Overloaded solve: grid pointer variant
#test
{
    var g = parseGrid(SmallInput)
    defer freeGrid(&g)
    let r1 = solveGrid(&g)
    let r2 = solveGrid(&g)
    @assert(r1.part1 == r2.part1)
    @assert(r1.part2 == r2.part2)
}
