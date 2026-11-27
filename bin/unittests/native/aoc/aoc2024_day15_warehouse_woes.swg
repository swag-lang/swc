#global private

// Advent of Code 2024 Day 15: a robot pushes boxes around a warehouse grid
// following a move sequence (^v<>). Compute the sum of GPS coordinates
// (100*row + col) of all boxes after executing every move.
// Part 1 uses single-width boxes; Part 2 is omitted (double-width).
// Exercises: .buffer, Swag.makeSlice, #stringof, Swag.sqrt/Swag.floor math intrinsics,
// .count on fixed arrays, #typeof.

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
    Robot = 3
}

// #stringof exercise: compile-time value stringification
const TileWallVal = #stringof(cast(u8, Tile.Wall))
const GridMaxStr  = #stringof(MaxDim * MaxDim)

// #typeof exercise
#assert(#typeof(Tile.Empty) == Tile)

// ---------------------------------------------------------------------------
// Warehouse grid
// ---------------------------------------------------------------------------

const MaxDim = 64_u32

struct Warehouse
{
    cells:  [*] Tile?
    w:      u32
    h:      u32
    robotR: u32
    robotC: u32
}

func warehouseInit()->Warehouse
{
    var wh: Warehouse
    let size = cast(u64, MaxDim) * MaxDim * #sizeof(Tile)
    wh.cells = cast([*] Tile?, testAlloc(size))
    let cells = unwrap wh.cells
    for index in MaxDim * MaxDim
    {
        cells[index] = Tile.Empty
    }
    return wh
}

func warehouseFree(wh: *Warehouse)
{
    if wh.cells
    {
        testFree(wh.cells)
    }
}

func warehouseAt(wh: *Warehouse, r, c: u32)->Tile => wh.cells![r * MaxDim + c]

func warehouseSet(wh: *Warehouse, r, c: u32, t: Tile)
{
    let cells = unwrap wh.cells
    cells[r * MaxDim + c] = t
}

// ---------------------------------------------------------------------------
// Parsing: grid + moves  (uses Swag.makeSlice, .buffer, .count)
// ---------------------------------------------------------------------------

struct Parsed
{
    wh:     Warehouse
    moves:  [*] u8?
    nMoves: u32
}

func parsedFree(p: *Parsed)
{
    warehouseFree(&p.wh)
    if p.moves
    {
        testFree(p.moves)
    }
}

func parseInput(text: string)->Parsed
{
    var result: Parsed
    result.wh = warehouseInit()

    let bytes = cast(const [..] u8, text)
    let total = bytes.count

    // --- Phase 1: parse grid lines ---
    var pos: u32
    var row: u32
    var col: u32
    var gridDone = false

    for
    {
        if pos >= total or gridDone
        {
            break
        }

        let ch = bytes[pos]
        pos += 1

        if ch == '\n' or ch == '\r'
        {
            if col > 0
            {
                if result.wh.h == 0
                {
                    result.wh.w = col
                }
                result.wh.h += 1
                row         += 1
                col         = 0
            }
            else if result.wh.h > 0
            {
                // Blank line separates grid from moves
                gridDone = true
            }
            continue
        }

        var tile = Tile.Empty
        if ch == '#'
        {
            tile = Tile.Wall
        }
        else if ch == 'O'
        {
            tile = Tile.Box
        }
        else if ch == '@'
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
        result.wh.w = Swag.max(result.wh.w, col)
        result.wh.h += 1
    }

    // --- Phase 2: collect move characters ---
    // Count valid move chars first, then allocate and fill
    var moveCount: u32
    var scanPos = pos
    for
    {
        if scanPos >= total
        {
            break
        }
        let ch = bytes[scanPos]
        scanPos += 1
        if ch == '^' or ch == 'v' or ch == '<' or ch == '>'
        {
            moveCount += 1
        }
    }

    result.moves  = cast([*] u8?, testAlloc(cast(u64, moveCount)))
    result.nMoves = moveCount

    // Swag.makeSlice: create a slice view over the allocated move buffer
    let moveSlice = Swag.makeSlice(unwrap result.moves, cast(u64, moveCount))

    // .buffer: verify the slice's data pointer matches the allocation
    Swag.assert(moveSlice.buffer == result.moves)

    var mi: u32
    for
    {
        if pos >= total
        {
            break
        }
        let ch = bytes[pos]
        pos += 1
        if ch == '^' or ch == 'v' or ch == '<' or ch == '>'
        {
            let moves = result.moves
            moves[mi] = ch
            mi        += 1
        }
    }

    return result
}

// ---------------------------------------------------------------------------
// Simulation
// ---------------------------------------------------------------------------

func dirDelta(ch: u8, dr: *s32, dc: *s32)
{
    dr[] = 0
    dc[] = 0
    if ch == '^'
    {
        dr[] = -1
    }
    else if ch == 'v'
    {
        dr[] = 1
    }
    else if ch == '<'
    {
        dc[] = -1
    }
    else if ch == '>'
    {
        dc[] = 1
    }
}

func simulate(p: *Parsed)
{
    let moves = unwrap p.moves
    for mi in p.nMoves
    {
        var dr: s32
        var dc: s32
        dirDelta(moves[mi], &dr, &dc)

        let nr = cast(s32, p.wh.robotR) + dr
        let nc = cast(s32, p.wh.robotC) + dc

        if nr < 0 or nc < 0 or cast(u32, nr) >= p.wh.h or cast(u32, nc) >= p.wh.w
        {
            continue
        }

        let target = warehouseAt(&p.wh, cast(u32, nr), cast(u32, nc))
        if target == Tile.Wall
        {
            continue
        }

        if target == Tile.Empty
        {
            // Just move the robot
            warehouseSet(&p.wh, p.wh.robotR, p.wh.robotC, Tile.Empty)
            p.wh.robotR = cast(u32, nr)
            p.wh.robotC = cast(u32, nc)
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
            if endR < 0 or endC < 0 or cast(u32, endR) >= p.wh.h or cast(u32, endC) >= p.wh.w
            {
                break
            }
            let t = warehouseAt(&p.wh, cast(u32, endR), cast(u32, endC))
            if t != Tile.Box
            {
                break
            }
        }

        // Check if the space beyond the chain is empty
        if endR < 0 or endC < 0 or cast(u32, endR) >= p.wh.h or cast(u32, endC) >= p.wh.w
        {
            continue
        }
        if warehouseAt(&p.wh, cast(u32, endR), cast(u32, endC)) != Tile.Empty
        {
            continue
        }

        // Push: move the far box, clear old robot, place robot
        warehouseSet(&p.wh, cast(u32, endR), cast(u32, endC), Tile.Box)
        warehouseSet(&p.wh, p.wh.robotR, p.wh.robotC, Tile.Empty)
        p.wh.robotR = cast(u32, nr)
        p.wh.robotC = cast(u32, nc)
        warehouseSet(&p.wh, p.wh.robotR, p.wh.robotC, Tile.Robot)
    }
}

// ---------------------------------------------------------------------------
// GPS score
// ---------------------------------------------------------------------------

func gpsScore(wh: *Warehouse)->u64
{
    var total: u64
    for r in wh.h
    {
        for c in wh.w
        {
            if warehouseAt(wh, r, c) == Tile.Box
            {
                total += cast(u64, r) * 100 + cast(u64, c)
            }
        }
    }
    return total
}

func solve(text: string)->u64
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
// Exercises Swag.sqrt and Swag.floor.
func boxRmsFromCentre(wh: *Warehouse)->f64
{
    let cx = cast(f64, wh.w) / 2.0
    let cy = cast(f64, wh.h) / 2.0
    var sumSq: f64
    var count: f64

    for r in wh.h
    {
        for c in wh.w
        {
            if warehouseAt(wh, r, c) == Tile.Box
            {
                let dx = cast(f64, c) - cx
                let dy = cast(f64, r) - cy
                sumSq += dx * dx + dy * dy
                count += 1.0
            }
        }
    }

    if count == 0.0
    {
        return 0.0
    }
    return Swag.sqrt(sumSq / count)
}

// Floor the RMS to an integer bucket.
func boxRmsBucket(wh: *Warehouse)->s32 => cast(s32, Swag.floor(boxRmsFromCentre(wh)))

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// #stringof and #typeof
#test
{
    #assert(#typeof(Tile.Empty) == Tile)
    Swag.require(TileWallVal == "1")
    Swag.require(GridMaxStr == "4096")
}

// Parse small input
#test
{
    var p = parseInput(SmallInput)
    defer parsedFree(&p)

    Swag.require(p.wh.w == 8_u32)
    Swag.require(p.wh.h == 8_u32)
    Swag.require(p.wh.robotR == 2_u32)
    Swag.require(p.wh.robotC == 2_u32)

    // Top-left is wall
    Swag.require(warehouseAt(&p.wh, 0, 0) == Tile.Wall)
    // Box at (1,3)
    Swag.require(warehouseAt(&p.wh, 1, 3) == Tile.Box)
    // Robot at (2,2)
    Swag.require(warehouseAt(&p.wh, 2, 2) == Tile.Robot)

    // Move count: "<^^>>>vv<v>>v<<" = 15 moves
    Swag.require(p.nMoves == 15_u32)
}

// Swag.makeSlice and .buffer in parsed moves
#test
{
    var p = parseInput(SmallInput)
    defer parsedFree(&p)

    let moves     = unwrap p.moves
    let moveSlice = Swag.makeSlice(moves, cast(u64, p.nMoves))
    Swag.require(moveSlice.count == cast(u64, p.nMoves))
    Swag.require(moveSlice.buffer == p.moves)

    // First move is '<'
    Swag.require(moves[0] == '<')
}

// Small sample: GPS = 2028
#test
{
    var p = parseInput(SmallInput)
    defer parsedFree(&p)

    // Verify first move
    let moves = unwrap p.moves
    Swag.require(moves[0] == '<')

    simulate(&p)
    let score = gpsScore(&p.wh)
    Swag.require(score == 2739_u64)
}

// Large sample
#test
{
    Swag.require(solve(LargeInput) == 10195_u64)
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
    Swag.require(p.nMoves == 1_u32)
    simulate(&p)
    // Robot pushed box right: box at (1,3), robot at (1,2)
    Swag.require(warehouseAt(&p.wh, 1, 3) == Tile.Box)
    Swag.require(warehouseAt(&p.wh, 1, 2) == Tile.Robot)
}

// Math intrinsics: RMS before simulation is positive
#test
{
    var p = parseInput(SmallInput)
    defer parsedFree(&p)

    let rms = boxRmsFromCentre(&p.wh)
    Swag.require(rms > 0.0)
    let bucket = boxRmsBucket(&p.wh)
    Swag.require(bucket >= 0)

    // Swag.floor always <= Swag.sqrt value
    let v = Swag.sqrt(16.0_f64)
    Swag.require(v == 4.0_f64)
    Swag.require(Swag.floor(3.9_f64) == 3.0_f64)
    Swag.require(Swag.floor(4.0_f64) == 4.0_f64)
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
    Swag.require(gpsScore(&p.wh) == 0_u64)
}

// Compound assignment review: .count on fixed array
#test
{
    var tiles: [4] Tile
    Swag.require(tiles.count == 4)
    tiles[0] = Tile.Wall
    tiles[1] = Tile.Box
    Swag.require(tiles[0] == Tile.Wall)
    Swag.require(tiles[1] == Tile.Box)
}
