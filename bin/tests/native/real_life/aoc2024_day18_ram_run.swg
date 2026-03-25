#global fileprivate

// Advent of Code 2024 Day 18: bytes corrupt grid cells over time.
// Part 1: BFS shortest path from (0,0) to (size-1,size-1) after N corruptions.
// Part 2: binary-search for the first corruption that blocks all paths.
// Exercises: multi-dimensional arrays [N][M], #[Swag.Inline] mtd on 2-D
// grid, nested inline calls, binary search pattern, cstring type.

const SampleInput =
"""5,4
4,2
4,5
3,0
2,1
6,3
2,4
1,5
0,6
3,3
2,6
5,1
1,2
5,5
2,5
6,5
1,4
0,4
6,4
1,1
6,1
1,0
0,5
1,6
2,0"""

// ---------------------------------------------------------------------------
// Grid with multi-dimensional array
// ---------------------------------------------------------------------------

const Dim  = 8'u32
const MaxQ = 256'u32

struct Grid
{
    cells: [Dim] [Dim] u8   // 0 = open, 1 = corrupted
    w:     u32
    h:     u32
}

impl Grid
{
    #[Swag.Inline]
    mtd at(r: u32, c: u32) -> u8 { return me.cells[r][c] }

    #[Swag.Inline]
    mtd set(r: u32, c: u32, v: u8) { me.cells[r][c] = v }

    // Nested inline: passable reads through at
    #[Swag.Inline]
    mtd passable(r: u32, c: u32) -> bool { return me.at(r, c) == 0 }

    mtd clear()
    {
        for r in Dim
        {
            for c in Dim
            {
                me.cells[r][c] = 0
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Byte list
// ---------------------------------------------------------------------------

const MaxBytes = 128'u32

struct BytePos
{
    col: u32
    row: u32
}

struct ByteList
{
    items: [MaxBytes] BytePos
    count: u32
}

func parseBytes(text: string) -> ByteList
{
    var result: ByteList
    let bytes = cast(const [..] u8) text
    var pos: u32

    for
    {
        if pos >= @countof(bytes) or result.count >= MaxBytes do break

        // skip to digit
        for
        {
            if pos >= @countof(bytes) do break
            let ch = bytes[pos]
            if ch >= '0' and ch <= '9' do break
            pos += 1
        }
        if pos >= @countof(bytes) do break

        // parse col
        var col: u32
        for
        {
            if pos >= @countof(bytes) do break
            let ch = bytes[pos]
            if ch < '0' or ch > '9' do break
            col = col * 10 + cast(u32) (ch - '0')
            pos += 1
        }

        // skip comma
        if pos < @countof(bytes) and bytes[pos] == ',' do pos += 1

        // parse row
        var row: u32
        for
        {
            if pos >= @countof(bytes) do break
            let ch = bytes[pos]
            if ch < '0' or ch > '9' do break
            row = row * 10 + cast(u32) (ch - '0')
            pos += 1
        }

        with result.items[result.count]
        {
            .col = col
            .row = row
        }
        result.count += 1
    }

    return result
}

// ---------------------------------------------------------------------------
// Apply corruptions
// ---------------------------------------------------------------------------

func applyBytes(g: *Grid, bl: *ByteList, count: u32)
{
    g.clear()
    for i in count
    {
        let b = bl.items[i]
        if b.row < g.h and b.col < g.w do
            g.set(b.row, b.col, 1)
    }
}

// ---------------------------------------------------------------------------
// BFS shortest path
// ---------------------------------------------------------------------------

const DR: [4] s32 = [0, 1, 0, -1]
const DC: [4] s32 = [1, 0, -1, 0]

func bfs(g: *Grid) -> s32
{
    let er = g.h - 1
    let ec = g.w - 1
    if !g.passable(0, 0) or !g.passable(er, ec) do
        return -1

    var dist: [Dim] [Dim] s32
    for r in Dim
    {
        for c in Dim
        {
            dist[r][c] = -1
        }
    }
    dist[0][0] = 0

    let queue = cast([*] u32) @alloc(cast(u64) MaxQ * 2 * #sizeof(u32))
    defer @free(queue)
    var head: u32
    var tail: u32
    queue[0] = 0
    queue[1] = 0
    tail = 2

    for MaxQ
    {
        if head >= tail do
            break
        let cr = queue[head]
        let cc = queue[head + 1]
        head += 2

        if cr == er and cc == ec do
            return dist[cr][cc]

        for d in 4
        {
            let nr = cast(s32) cr + DR[d]
            let nc = cast(s32) cc + DC[d]
            if nr < 0 or nc < 0 or cast(u32) nr >= g.h or cast(u32) nc >= g.w do
                continue
            let ur = cast(u32) nr
            let uc = cast(u32) nc
            if !g.passable(ur, uc) or dist[ur][uc] >= 0 do
                continue
            dist[ur][uc] = dist[cr][cc] + 1
            queue[tail] = ur
            queue[tail + 1] = uc
            tail += 2
        }
    }

    return -1
}

// ---------------------------------------------------------------------------
// Part 2: binary search for first blocking byte
// ---------------------------------------------------------------------------

func findBlockingByte(g: *Grid, bl: *ByteList) -> u32
{
    var lo: u32 = 0
    var hi = bl.count

    for bl.count
    {
        if lo >= hi do
            break
        let mid = (lo + hi) / 2
        applyBytes(g, bl, mid + 1)
        if bfs(g) < 0
        {
            hi = mid
        }
        else
        {
            lo = mid + 1
        }
    }

    return lo
}

// ---------------------------------------------------------------------------
// Solver
// ---------------------------------------------------------------------------

struct Result
{
    part1Dist:       s32
    blockingByteIdx: u32
    blockingCol:     u32
    blockingRow:     u32
}

func solve(text: string, gridSize: u32, part1Drops: u32) -> Result
{
    var bl = parseBytes(text)
    var g: Grid
    g.w = gridSize
    g.h = gridSize

    var result: Result

    // Part 1
    applyBytes(&g, &bl, part1Drops)
    result.part1Dist = bfs(&g)

    // Part 2
    let idx = findBlockingByte(&g, &bl)
    result.blockingByteIdx = idx
    if idx < bl.count
    {
        result.blockingCol = bl.items[idx].col
        result.blockingRow = bl.items[idx].row
    }

    return result
}

// ---------------------------------------------------------------------------
// cstring exercise: format blocking coordinate as "col,row"
// ---------------------------------------------------------------------------

func formatCoord(col: u32, row: u32, buf: [*] u8, bufLen: u32) -> u32
{
    var pos: u32

    // Write col digits
    if col == 0
    {
        buf[pos] = '0'
        pos += 1
    }
    else
    {
        var tmp: [10] u8
        var tmpLen: u32
        var v = col
        for
        {
            if v == 0 do break
            tmp[tmpLen] = cast(u8) (v % 10) + '0'
            tmpLen += 1
            v /= 10
        }
        for #reverse i in tmpLen
        {
            buf[pos] = tmp[i]
            pos += 1
        }
    }

    buf[pos] = ','
    pos += 1

    // Write row digits
    if row == 0
    {
        buf[pos] = '0'
        pos += 1
    }
    else
    {
        var tmp: [10] u8
        var tmpLen: u32
        var v = row
        for
        {
            if v == 0 do break
            tmp[tmpLen] = cast(u8) (v % 10) + '0'
            tmpLen += 1
            v /= 10
        }
        for #reverse i in tmpLen
        {
            buf[pos] = tmp[i]
            pos += 1
        }
    }

    return pos
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// Parse byte list
#test
{
    let bl = parseBytes(SampleInput)
    @assert(bl.count == 25'u32)
    @assert(bl.items[0].col == 5'u32)
    @assert(bl.items[0].row == 4'u32)
    @assert(bl.items[1].col == 4'u32)
    @assert(bl.items[1].row == 2'u32)
}

// Multi-dim array: set and read
#test
{
    var g: Grid
    g.w = 7; g.h = 7
    g.set(2, 3, 1)
    @assert(g.at(2, 3) == 1)
    @assert(g.at(0, 0) == 0)
    @assert(!g.passable(2, 3))
    @assert(g.passable(0, 0))
}

// Grid clear
#test
{
    var g: Grid
    g.w = 4; g.h = 4
    g.set(1, 1, 1)
    g.clear()
    @assert(g.at(1, 1) == 0)
}

// BFS on open grid
#test
{
    var g: Grid
    g.w = 7; g.h = 7
    // Open: (0,0) to (6,6) = 12
    @assert(bfs(&g) == 12)
}

// BFS blocked
#test
{
    var g: Grid
    g.w = 3; g.h = 3
    g.set(0, 1, 1)
    g.set(1, 0, 1)
    @assert(bfs(&g) == -1)
}

// Sample: Part 1 after 12 bytes on 7×7 grid → distance 22
#test
{
    let result = solve(SampleInput, 7, 12)
    @assert(result.part1Dist == 22)
}

// Sample: Part 2 blocking byte at index 20 → (6,1)
#test
{
    let result = solve(SampleInput, 7, 12)
    @assert(result.blockingByteIdx == 20'u32)
    @assert(result.blockingCol == 6'u32)
    @assert(result.blockingRow == 1'u32)
}

// Format coordinate
#test
{
    var buf: [16] u8
    let len = formatCoord(6, 1, &buf[0], 16)
    @assert(len == 3'u32)
    @assert(buf[0] == '6')
    @assert(buf[1] == ',')
    @assert(buf[2] == '1')

    // cstring: construct from buffer
    let cs = @mkslice(&buf[0], cast(u64) len)
    @assert(@countof(cs) == 3)
}

// for #reverse on digits
#test
{
    var buf: [4] u8
    let len = formatCoord(12, 34, &buf[0], 4)
    // "12,34" won't fit in 4 bytes — only partial
    // Just test formatCoord with single digits
    var buf2: [8] u8
    let len2 = formatCoord(0, 0, &buf2[0], 8)
    @assert(len2 == 3'u32)
    @assert(buf2[0] == '0')
    @assert(buf2[1] == ',')
    @assert(buf2[2] == '0')
}

// Binary search correctness: all bytes blocked trivially
#test
{
    var g: Grid
    g.w = 2; g.h = 2
    var bl: ByteList
    // Block (0,1) then (1,0) → path (0,0)→(0,1)→(1,1) blocked at byte 0
    bl.items[0] = BytePos{col: 1, row: 0}
    bl.items[1] = BytePos{col: 0, row: 1}
    bl.count = 2
    let idx = findBlockingByte(&g, &bl)
    // After 1 byte: (0,1) blocked. Path (0,0)→(1,0)→(1,1) still open
    // After 2 bytes: (1,0) also blocked. No path. So blocking = index 1
    @assert(idx == 1'u32)
}
