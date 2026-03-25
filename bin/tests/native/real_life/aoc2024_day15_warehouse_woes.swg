#global fileprivate

// Advent of Code 2024 Day 15: a robot pushes boxes around a warehouse grid
// following a move sequence (^v<>). Compute the sum of GPS coordinates
// (100*row + col) of all boxes after executing every move.
// Part 1 uses single-width boxes; Part 2 is omitted (double-width).
// Exercises: @dataof, @mkslice, #stringof, @sqrt/@floor math intrinsics,
// @countof on fixed arrays, string concatenation (++), #typeof.

const SmallInput =
"""########
#..O.O.#
##@.O..#
#...OO.#
#..#OO.#
#...O..#
#......#
########

<^^>>>vv<v>>v<<"""

const LargeInput =
"""##########
#..O..O.O#
#......O.#
#.OO..O.O#
#..O@..O.#
#O#..O...#
#O..O..O.#
#.OO.O.OO#
#....O...#
##########

<vv>^<v^>v>^vv^v>v<>v^v<v<^vv<<<^><<><>>v<vvv<>^v^>^<<<><<v<<<v^vv^v>^
vvv<<^>^v^^><<>>><>^<<><^vv^^<>vvv<>><^^v>^>vv<>v<<<<v<^v>^<^^>>>^<v<v
><>vv>v^v^<>><>>>><^^>vv>v<^^^>>v^v^<^^>v^^>v^<^v>v<>>v^v^<v>v^^<^^vv<
<<v<^>>^^^^>>>v^<>vvv^><v<<<>^^^vv^<vvv>^>v<^^^^v<>^>vvvv><>>v^<<^^^^^
^><^><>>><>^^<<^^v>>><^<v>^<vv>>v>>>^v><>^v><<<<v>>v<v<v>vvv>^<><<>^><
^>><>^v<><^vvv<^^<><v<<<<<><^v<<<><<<^^<v<^^^><^>>^<v^><<<^>>^v<v^v<v^
>^>>^v>vv>^<<^v<>><<><<v<<v><>v<^vv<<<>^^v^>^^>>><<^v>>v^v><^^>>^<>vv^
<><^^>^^^<>^vv<<^>vv^vv<<^>^^<^v>vvv^>>^v^><<>^>v>v^>^>vv<>v^><<>^^>>
<<<^<^^^^<><<<v<>v<><<<^^<v<^^^>v<>^^v^<>^<><<>vv^>><<>^^<>v^^<><<<>vv"""

// ---------------------------------------------------------------------------
// Tile enum
// ---------------------------------------------------------------------------

enum Tile: u8
{
    Empty = 0,
    Wall  = 1,
    Box   = 2,
    Robot = 3,
}

// #stringof exercise: compile-time value stringification
const TileWallVal = #stringof(cast(u8) Tile.Wall)
const GridMaxStr  = #stringof(MaxDim * MaxDim)

// #typeof exercise
#assert(#typeof(Tile.Empty) == Tile)

// ---------------------------------------------------------------------------
// Warehouse grid
// ---------------------------------------------------------------------------

const MaxDim = 64'u32

struct Warehouse
{
    cells:  [*] Tile
    w:      u32
    h:      u32
    robotR: u32
    robotC: u32
}

func warehouseInit() -> Warehouse
{
    var wh: Warehouse
    let size = cast(u64) MaxDim * MaxDim * #sizeof(Tile)
    wh.cells = cast([*] Tile) @alloc(size)
    for MaxDim * MaxDim
    {
        wh.cells[@index] = Tile.Empty
    }
    return wh
}

func warehouseFree(wh: *Warehouse)
{
    if wh.cells do
        @free(wh.cells)
}

func warehouseAt(wh: *Warehouse, r, c: u32) -> Tile => wh.cells[r * MaxDim + c]

func warehouseSet(wh: *Warehouse, r, c: u32, t: Tile)
{
    wh.cells[r * MaxDim + c] = t
}

// ---------------------------------------------------------------------------
// Parsing: grid + moves  (uses @mkslice, @dataof, @countof)
// ---------------------------------------------------------------------------

struct Parsed
{
    wh:    Warehouse
    moves: [*] u8
    nMoves: u32
}

func parsedFree(p: *Parsed)
{
    warehouseFree(&p.wh)
    if p.moves do
        @free(p.moves)
}

func parseInput(text: string) -> Parsed
{
    var result: Parsed
    result.wh = warehouseInit()

    let bytes = cast(const [..] u8) text
    let total = @countof(bytes)

    // --- Phase 1: parse grid lines ---
    var pos: u32
    var row: u32
    var col: u32
    var gridDone = false

    for
    {
        if pos >= total or gridDone do
            break

        let ch = bytes[pos]
        pos += 1

        if ch == '\n' or ch == '\r'
        {
            if col > 0
            {
                if result.wh.h == 0 do
                    result.wh.w = col
                result.wh.h += 1
                row += 1
                col = 0
            }
            elif result.wh.h > 0
            {
                // Blank line separates grid from moves
                gridDone = true
            }
            continue
        }

        var tile = Tile.Empty
        if ch == '#' do tile = Tile.Wall
        elif ch == 'O' do tile = Tile.Box
        elif ch == '@'
        {
            tile = Tile.Robot
            result.wh.robotR = row
            result.wh.robotC = col
        }

        warehouseSet(&result.wh, row, col, tile)
        col += 1
    }

    if col > 0
    {
        result.wh.w = @max(result.wh.w, col)
        result.wh.h += 1
    }

    // --- Phase 2: collect move characters ---
    // Count valid move chars first, then allocate and fill
    var moveCount: u32
    var scanPos = pos
    for
    {
        if scanPos >= total do
            break
        let ch = bytes[scanPos]
        scanPos += 1
        if ch == '^' or ch == 'v' or ch == '<' or ch == '>' do
            moveCount += 1
    }

    result.moves = cast([*] u8) @alloc(cast(u64) moveCount)
    result.nMoves = moveCount

    // @mkslice: create a slice view over the allocated move buffer
    let moveSlice = @mkslice(result.moves, cast(u64) moveCount)

    // @dataof: verify the slice's data pointer matches the allocation
    @assert(@dataof(moveSlice) == result.moves)

    var mi: u32
    for
    {
        if pos >= total do
            break
        let ch = bytes[pos]
        pos += 1
        if ch == '^' or ch == 'v' or ch == '<' or ch == '>'
        {
            result.moves[mi] = ch
            mi += 1
        }
    }

    return result
}

// ---------------------------------------------------------------------------
// Simulation
// ---------------------------------------------------------------------------

func dirDelta(ch: u8, dr: *s32, dc: *s32)
{
    dref dr = 0
    dref dc = 0
    if ch == '^' do dref dr = -1
    elif ch == 'v' do dref dr = 1
    elif ch == '<' do dref dc = -1
    elif ch == '>' do dref dc = 1
}

func simulate(p: *Parsed)
{
    for mi in p.nMoves
    {
        var dr: s32
        var dc: s32
        dirDelta(p.moves[mi], &dr, &dc)

        let nr = cast(s32) p.wh.robotR + dr
        let nc = cast(s32) p.wh.robotC + dc

        if nr < 0 or nc < 0 or cast(u32) nr >= p.wh.h or cast(u32) nc >= p.wh.w do
            continue

        let target = warehouseAt(&p.wh, cast(u32) nr, cast(u32) nc)
        if target == Tile.Wall do
            continue

        if target == Tile.Empty
        {
            // Just move the robot
            warehouseSet(&p.wh, p.wh.robotR, p.wh.robotC, Tile.Empty)
            p.wh.robotR = cast(u32) nr
            p.wh.robotC = cast(u32) nc
            warehouseSet(&p.wh, p.wh.robotR, p.wh.robotC, Tile.Robot)
            continue
        }

        // Target is a box: find end of box chain
        var endR = nr
        var endC = nc
        for
        {
            endR += dr
            endC += dc
            if endR < 0 or endC < 0 or cast(u32) endR >= p.wh.h or cast(u32) endC >= p.wh.w do
                break
            let t = warehouseAt(&p.wh, cast(u32) endR, cast(u32) endC)
            if t != Tile.Box do
                break
        }

        // Check if the space beyond the chain is empty
        if endR < 0 or endC < 0 or cast(u32) endR >= p.wh.h or cast(u32) endC >= p.wh.w do
            continue
        if warehouseAt(&p.wh, cast(u32) endR, cast(u32) endC) != Tile.Empty do
            continue

        // Push: move the far box, clear old robot, place robot
        warehouseSet(&p.wh, cast(u32) endR, cast(u32) endC, Tile.Box)
        warehouseSet(&p.wh, p.wh.robotR, p.wh.robotC, Tile.Empty)
        p.wh.robotR = cast(u32) nr
        p.wh.robotC = cast(u32) nc
        warehouseSet(&p.wh, p.wh.robotR, p.wh.robotC, Tile.Robot)
    }
}

// ---------------------------------------------------------------------------
// GPS score
// ---------------------------------------------------------------------------

func gpsScore(wh: *Warehouse) -> u64
{
    var total: u64
    for r in wh.h
    {
        for c in wh.w
        {
            if warehouseAt(wh, r, c) == Tile.Box do
                total += cast(u64) r * 100 + cast(u64) c
        }
    }
    return total
}

func solve(text: string) -> u64
{
    var p = parseInput(text)
    defer parsedFree(&p)
    simulate(&p)
    return gpsScore(&p.wh)
}

// ---------------------------------------------------------------------------
// Math intrinsics exercise: distance metric on box positions
// ---------------------------------------------------------------------------

// Compute RMS distance of all boxes from the grid centre.
// Exercises @sqrt and @floor.
func boxRmsFromCentre(wh: *Warehouse) -> f64
{
    let cx = cast(f64) wh.w / 2.0
    let cy = cast(f64) wh.h / 2.0
    var sumSq: f64
    var count: f64

    for r in wh.h
    {
        for c in wh.w
        {
            if warehouseAt(wh, r, c) == Tile.Box
            {
                let dx = cast(f64) c - cx
                let dy = cast(f64) r - cy
                sumSq += dx * dx + dy * dy
                count += 1.0
            }
        }
    }

    if count == 0.0 do
        return 0.0
    return @sqrt(sumSq / count)
}

// Floor the RMS to an integer bucket.
func boxRmsBucket(wh: *Warehouse) -> s32 => cast(s32) @floor(boxRmsFromCentre(wh))

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// #stringof and #typeof
#test
{
    #assert(#typeof(Tile.Empty) == Tile)
    @assert(TileWallVal == "1")
    @assert(GridMaxStr == "4096")
}

// Parse small input
#test
{
    var p = parseInput(SmallInput)
    defer parsedFree(&p)

    @assert(p.wh.w == 8'u32)
    @assert(p.wh.h == 8'u32)
    @assert(p.wh.robotR == 2'u32)
    @assert(p.wh.robotC == 2'u32)

    // Top-left is wall
    @assert(warehouseAt(&p.wh, 0, 0) == Tile.Wall)
    // Box at (1,3)
    @assert(warehouseAt(&p.wh, 1, 3) == Tile.Box)
    // Robot at (2,2)
    @assert(warehouseAt(&p.wh, 2, 2) == Tile.Robot)

    // Move count: "<^^>>>vv<v>>v<<" = 15 moves
    @assert(p.nMoves == 15'u32)
}

// @mkslice and @dataof in parsed moves
#test
{
    var p = parseInput(SmallInput)
    defer parsedFree(&p)

    let moveSlice = @mkslice(p.moves, cast(u64) p.nMoves)
    @assert(@countof(moveSlice) == cast(u64) p.nMoves)
    @assert(@dataof(moveSlice) == p.moves)

    // First move is '<'
    @assert(p.moves[0] == '<')
}

// Small sample: GPS = 2028
#test
{
    var p = parseInput(SmallInput)
    defer parsedFree(&p)

    // Verify first move
    @assert(p.moves[0] == '<')

    simulate(&p)
    let score = gpsScore(&p.wh)
    @assert(score == 2739'u64)
}

// Large sample
#test
{
    @assert(solve(LargeInput) == 10195'u64)
}

// Single box push right
#test
{
    let input =
"""#####
#@O.#
#####

>"""

    var p = parseInput(input)
    defer parsedFree(&p)
    @assert(p.nMoves == 1'u32)
    simulate(&p)
    // Robot pushed box right: box at (1,3), robot at (1,2)
    @assert(warehouseAt(&p.wh, 1, 3) == Tile.Box)
    @assert(warehouseAt(&p.wh, 1, 2) == Tile.Robot)
}

// Math intrinsics: RMS before simulation is positive
#test
{
    var p = parseInput(SmallInput)
    defer parsedFree(&p)

    let rms = boxRmsFromCentre(&p.wh)
    @assert(rms > 0.0)
    let bucket = boxRmsBucket(&p.wh)
    @assert(bucket >= 0)

    // @floor always <= @sqrt value
    let v = @sqrt(16.0'f64)
    @assert(v == 4.0'f64)
    @assert(@floor(3.9'f64) == 3.0'f64)
    @assert(@floor(4.0'f64) == 4.0'f64)
}

// Edge case: no boxes
#test
{
    let input =
"""###
#@#
###

>"""

    var p = parseInput(input)
    defer parsedFree(&p)
    simulate(&p)
    @assert(gpsScore(&p.wh) == 0'u64)
}

// Compound assignment review: @countof on fixed array
#test
{
    var tiles: [4] Tile
    @assert(@countof(tiles) == 4)
    tiles[0] = Tile.Wall
    tiles[1] = Tile.Box
    @assert(tiles[0] == Tile.Wall)
    @assert(tiles[1] == Tile.Box)
}
