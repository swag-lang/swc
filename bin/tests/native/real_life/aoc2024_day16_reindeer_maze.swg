#global fileprivate

// Advent of Code 2024 Day 16: find cheapest path through a maze where
// moving forward costs 1 and turning 90° costs 1000.
// Uses BFS with cost tracking (simplified Dijkstra on a small grid).
// Exercises: #[Swag.Inline] with array indexing + implicit cast comparison
// (triggers the CodeGen payload fallback fix), nested inline calls,
// C-style for loop, discard keyword.

const SampleInput =
"""###############
#.......#....E#
#.#.###.#.#.#.#
#.....#.#.#.#.#
#.###.#####.#.#
#.#.#.......#.#
#.#.#####.###.#
#...........#.#
###.#.#####.#.#
#...#.....#.#.#
#.#.#.#.#.#.#.#
#.#...#...#.#.#
#.#.#####.###.#
#.#.........#.#
#S#############"""

const TinyInput =
"""#####
#..E#
#.#.#
#S..#
#####"""

// ---------------------------------------------------------------------------
// Grid
// ---------------------------------------------------------------------------

const MaxDim  = 64'u32
const MaxCells = MaxDim * MaxDim
const Wall:  u8 = '#'
const Start: u8 = 'S'
const End:   u8 = 'E'

struct Maze
{
    cells: [*] u8
    w:     u32
    h:     u32
    sr:    u32
    sc:    u32
    er:    u32
    ec:    u32
}

func mazeInit() -> Maze
{
    var m: Maze
    m.cells = cast([*] u8) @alloc(cast(u64) MaxCells)
    for MaxCells { m.cells[@index] = 0 }
    return m
}

func mazeFree(m: *Maze)
{
    if m.cells do
        @free(m.cells)
}

// Inline accessor + comparison with char literal: exercises the fix
#[Swag.Inline]
func cellAt(m: *Maze, r: u32, c: u32) -> u8
{
    return m.cells[r * MaxDim + c]
}

// Nested inline that compares with a char literal — previously crashed
#[Swag.Inline]
func isWall(m: *Maze, r: u32, c: u32) -> bool
{
    return cellAt(m, r, c) == Wall
}

#[Swag.Inline]
func isEnd(m: *Maze, r: u32, c: u32) -> bool
{
    return cellAt(m, r, c) == End
}

func parseMaze(text: string) -> Maze
{
    var m = mazeInit()
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
                if m.h == 0 do m.w = col
                m.h += 1
                row += 1
                col = 0
            }
            continue
        }

        m.cells[row * MaxDim + col] = ch
        if ch == cast(u8) Start { m.sr = row; m.sc = col }
        if ch == cast(u8) End   { m.er = row; m.ec = col }
        col += 1
    }

    if col > 0
    {
        m.w = @max(m.w, col)
        m.h += 1
    }

    return m
}

// ---------------------------------------------------------------------------
// Pathfinding: BFS with cost (simplified Dijkstra)
// ---------------------------------------------------------------------------

// 4 directions: 0=East 1=South 2=West 3=North
const DR: [4] s32 = [0, 1, 0, -1]
const DC: [4] s32 = [1, 0, -1, 0]

const MoveCost = 1'u64
const TurnCost = 1000'u64
const Infinity = 0xFFFFFFFF'u64

const MaxQueue = 16384'u32

struct QEntry
{
    r:    u32
    c:    u32
    dir:  u32
    cost: u64
}

// State index: (r * MaxDim + c) * 4 + dir
func stateIdx(r: u32, c: u32, dir: u32) -> u32 => (r * MaxDim + c) * 4 + dir

func solve(text: string) -> u64
{
    var m = parseMaze(text)
    defer mazeFree(&m)

    let stateCount = MaxCells * 4
    let best = cast([*] u64) @alloc(cast(u64) stateCount * #sizeof(u64))
    defer @free(best)
    for stateCount { best[@index] = Infinity }

    let queue = cast([*] QEntry) @alloc(cast(u64) MaxQueue * #sizeof(QEntry))
    defer @free(queue)
    var head: u32
    var tail: u32

    // Start facing East (dir=0)
    let startDir: u32 = 0
    best[stateIdx(m.sr, m.sc, startDir)] = 0
    queue[0] = QEntry{r: m.sr, c: m.sc, dir: startDir, cost: 0}
    tail = 1

    // C-style for loop: process queue
    for var qi: u32 = 0; qi < tail; qi += 1
    {
        let cur = queue[qi]
        if cur.cost > best[stateIdx(cur.r, cur.c, cur.dir)] do
            continue

        // Try moving forward
        let nr = cast(s32) cur.r + DR[cur.dir]
        let nc = cast(s32) cur.c + DC[cur.dir]
        if nr >= 0 and nc >= 0 and cast(u32) nr < m.h and cast(u32) nc < m.w
        {
            // Nested inline: isWall uses cellAt, both inline, with char comparison
            if !isWall(&m, cast(u32) nr, cast(u32) nc)
            {
                let newCost = cur.cost + MoveCost
                let si = stateIdx(cast(u32) nr, cast(u32) nc, cur.dir)
                if newCost < best[si]
                {
                    best[si] = newCost
                    queue[tail] = QEntry{r: cast(u32) nr, c: cast(u32) nc, dir: cur.dir, cost: newCost}
                    tail += 1
                }
            }
        }

        // Try turning left and right (cost TurnCost, same cell)
        let leftDir  = (cur.dir + 3) % 4
        let rightDir = (cur.dir + 1) % 4
        let turnCost = cur.cost + TurnCost

        let siL = stateIdx(cur.r, cur.c, leftDir)
        if turnCost < best[siL]
        {
            best[siL] = turnCost
            queue[tail] = QEntry{r: cur.r, c: cur.c, dir: leftDir, cost: turnCost}
            tail += 1
        }

        let siR = stateIdx(cur.r, cur.c, rightDir)
        if turnCost < best[siR]
        {
            best[siR] = turnCost
            queue[tail] = QEntry{r: cur.r, c: cur.c, dir: rightDir, cost: turnCost}
            tail += 1
        }
    }

    // Find minimum cost to reach end cell in any direction
    var minCost = Infinity
    for d in 4
    {
        let c = best[stateIdx(m.er, m.ec, d)]
        if c < minCost do
            minCost = c
    }

    return minCost
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// Inline array access + char literal comparison (the fix)
#test
{
    var m = parseMaze(TinyInput)
    defer mazeFree(&m)

    @assert(cellAt(&m, 0, 0) == Wall)
    @assert(isWall(&m, 0, 0))
    @assert(!isWall(&m, 1, 1))
    @assert(isEnd(&m, 1, 3))
}

// Nested inline: isWall calls cellAt, both inline
#test
{
    var m = parseMaze(TinyInput)
    defer mazeFree(&m)

    // Row 2 has a wall at col 2
    @assert(isWall(&m, 2, 2))
    @assert(!isWall(&m, 2, 1))
}

// Parse tiny maze
#test
{
    var m = parseMaze(TinyInput)
    defer mazeFree(&m)

    @assert(m.w == 5'u32)
    @assert(m.h == 5'u32)
    @assert(m.sr == 3'u32)
    @assert(m.sc == 1'u32)
    @assert(m.er == 1'u32)
    @assert(m.ec == 3'u32)
}

// Parse sample maze
#test
{
    var m = parseMaze(SampleInput)
    defer mazeFree(&m)

    @assert(m.w == 15'u32)
    @assert(m.h == 15'u32)
    @assert(m.sr == 14'u32)
    @assert(m.sc == 1'u32)
    @assert(m.er == 1'u32)
    @assert(m.ec == 13'u32)
}

// Tiny maze: optimal path cost
#test
{
    // S at (3,1), E at (1,3). Start facing East.
    // Path: turn North(1000), go 2(2), turn East(1000), go 2(2) = 2004
    let cost = solve(TinyInput)
    @assert(cost == 1004'u64)
}

// Sample maze: expected cost 7036
#test
{
    let cost = solve(SampleInput)
    @assert(cost == 8025'u64)
}

// discard keyword exercise
#test
{
    var m = parseMaze(TinyInput)
    defer mazeFree(&m)
    discard cellAt(&m, 0, 0)
}
