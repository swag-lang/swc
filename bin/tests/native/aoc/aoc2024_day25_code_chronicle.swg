#global fileprivate

// Advent of Code 2024 Day 25: Code Chronicle
// Part 1: count lock/key pairs that fit without overlapping.
// Part 2: (traditional Day 25 — collect all other stars).
// Exercises: struct methods, nested inline struct methods, array of
// fixed-size arrays, for loops with until, struct equality, with &ptr
// blocks, heap allocation for dynamic collections, multi-line string
// parsing, cast chains, compile-time constants, @countof on slices,
// for #reverse, inline retval struct return.
// Note: fits/eq are non-inline due to compiler bug #5920 (inline return
// inside for loop never fires).

const SampleInput =
"""#####
.####
.####
.####
.#.#.
.#...
.....

#####
##.##
.#.##
...##
...#.
...#.
.....

.....
#....
#....
#...#
#.#.#
#.###
#####

.....
.....
#.#..
###..
###.#
###.#
#####

.....
.....
.....
#....
#.#..
#.#.#
#####"""

// ---------------------------------------------------------------------------
// Pin heights: 5 columns, each 0-5
// ---------------------------------------------------------------------------

const NumCols   = 5'u32
const MaxHeight = 5'u32
const GridRows  = 7'u32   // each schematic is 7 rows

struct Heights
{
    col: [NumCols] u8
}

impl Heights
{
    mtd fits(other: Heights) -> bool
    {
        for i in NumCols
        {
            if cast(u32) me.col[i] + cast(u32) other.col[i] > MaxHeight
            {
                return false
            }
        }
        return true
    }

    mtd eq(other: Heights) -> bool
    {
        for i in NumCols
        {
            if me.col[i] != other.col[i] do return false
        }
        return true
    }
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

const MaxSchematics = 512'u32

struct ParseResult
{
    locks:    [*] Heights
    keys:     [*] Heights
    lockCount: u32
    keyCount:  u32
}

func parseInit() -> ParseResult
{
    var r: ParseResult
    r.locks = cast([*] Heights) @alloc(cast(u64) MaxSchematics * #sizeof(Heights))
    r.keys  = cast([*] Heights) @alloc(cast(u64) MaxSchematics * #sizeof(Heights))
    return r
}

func parseFree(r: *ParseResult)
{
    if r.locks do @free(r.locks)
    if r.keys  do @free(r.keys)
}

// Parse a single 7-row schematic starting at `startPos`.
// Returns the position after the schematic (past trailing blank line).
func parseOneSchematic(bytes: const [..] u8, startPos: u32, result: *ParseResult) -> u32
{
    var pos = startPos

    // Skip leading whitespace/blank lines
    for
    {
        if pos >= @countof(bytes) do break
        if bytes[pos] != '\n' and bytes[pos] != '\r' do break
        pos += 1
    }

    if pos >= @countof(bytes) do return pos

    // Read 7 rows × 5 cols
    var grid: [GridRows] [NumCols] u8
    for row in GridRows
    {
        for col in NumCols
        {
            if pos < @countof(bytes)
            {
                grid[row][col] = bytes[pos]
                pos += 1
            }
        }
        // Skip line ending
        for
        {
            if pos >= @countof(bytes) do break
            if bytes[pos] != '\n' and bytes[pos] != '\r' do break
            pos += 1
        }
    }

    // Determine if lock (top row all '#') or key (top row all '.')
    let isLock = grid[0][0] == '#'

    var h: Heights
    if isLock
    {
        // Count '#' from top down per column (excluding row 0)
        for col in NumCols
        {
            var count: u8
            for row in 1 until GridRows
            {
                if grid[row][col] == '#' do count += 1
                else do break
            }
            h.col[col] = count
        }
        result.locks[result.lockCount] = h
        result.lockCount += 1
    }
    else
    {
        // Count '#' from bottom up per column (excluding last row)
        for col in NumCols
        {
            var count: u8
            for #reverse row in 1 until GridRows
            {
                if grid[row - 1][col] == '#' do count += 1
                else do break
            }
            h.col[col] = count
        }
        result.keys[result.keyCount] = h
        result.keyCount += 1
    }

    return pos
}

func parse(text: string) -> ParseResult
{
    var result = parseInit()
    let bytes = cast(const [..] u8) text
    var pos: u32

    for
    {
        if pos >= @countof(bytes) do break
        let newPos = parseOneSchematic(bytes, pos, &result)
        if newPos == pos do break  // no progress
        pos = newPos
    }

    return result
}

// ---------------------------------------------------------------------------
// Part 1: count fitting pairs
// ---------------------------------------------------------------------------

func countFittingPairs(r: *ParseResult) -> u64
{
    var count: u64
    for li in r.lockCount
    {
        for ki in r.keyCount
        {
            if r.locks[li].fits(r.keys[ki])
            {
                count += 1
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
}

func solve(text: string) -> SolveResult
{
    var pr = parse(text)
    defer parseFree(&pr)

    var result: SolveResult
    result.part1 = countFittingPairs(&pr)
    return result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// Heights.fits inline method
#test
{
    var lock: Heights
    lock.col[0] = 0; lock.col[1] = 5; lock.col[2] = 3; lock.col[3] = 4; lock.col[4] = 3

    var key: Heights
    key.col[0] = 3; key.col[1] = 0; key.col[2] = 2; key.col[3] = 0; key.col[4] = 1

    // 0+3=3, 5+0=5, 3+2=5, 4+0=4, 3+1=4 → all ≤ 5 → fits
    @assert(lock.fits(key))
}

// Heights.fits overlap
#test
{
    var lock: Heights
    lock.col[0] = 0; lock.col[1] = 5; lock.col[2] = 3; lock.col[3] = 4; lock.col[4] = 3

    var key: Heights
    key.col[0] = 5; key.col[1] = 0; key.col[2] = 2; key.col[3] = 1; key.col[4] = 3

    // col 4: 3+3=6 > 5 → overlap
    @assert(!lock.fits(key))
}

// Heights.eq inline method
#test
{
    var a: Heights
    a.col[0] = 1; a.col[1] = 2; a.col[2] = 3; a.col[3] = 4; a.col[4] = 5

    var b: Heights
    b.col[0] = 1; b.col[1] = 2; b.col[2] = 3; b.col[3] = 4; b.col[4] = 5

    @assert(a.eq(b))
    b.col[3] = 0
    @assert(!a.eq(b))
}

// Parse lock from sample
#test
{
    var pr = parse(SampleInput)
    defer parseFree(&pr)

    @assert(pr.lockCount == 2'u32)
    @assert(pr.keyCount == 3'u32)

    // Lock 1: 0,5,3,4,3
    @assert(pr.locks[0].col[0] == 0)
    @assert(pr.locks[0].col[1] == 5)
    @assert(pr.locks[0].col[2] == 3)
    @assert(pr.locks[0].col[3] == 4)
    @assert(pr.locks[0].col[4] == 3)

    // Lock 2: 1,2,0,5,3
    @assert(pr.locks[1].col[0] == 1)
    @assert(pr.locks[1].col[1] == 2)
    @assert(pr.locks[1].col[2] == 0)
    @assert(pr.locks[1].col[3] == 5)
    @assert(pr.locks[1].col[4] == 3)
}

// Parse keys from sample
#test
{
    var pr = parse(SampleInput)
    defer parseFree(&pr)

    // Key 1: 5,0,2,1,3
    @assert(pr.keys[0].col[0] == 5)
    @assert(pr.keys[0].col[1] == 0)
    @assert(pr.keys[0].col[2] == 2)
    @assert(pr.keys[0].col[3] == 1)
    @assert(pr.keys[0].col[4] == 3)

    // Key 2: 4,3,4,0,2
    @assert(pr.keys[1].col[0] == 4)
    @assert(pr.keys[1].col[1] == 3)
    @assert(pr.keys[1].col[2] == 4)
    @assert(pr.keys[1].col[3] == 0)
    @assert(pr.keys[1].col[4] == 2)

    // Key 3: 3,0,2,0,1
    @assert(pr.keys[2].col[0] == 3)
    @assert(pr.keys[2].col[1] == 0)
    @assert(pr.keys[2].col[2] == 2)
    @assert(pr.keys[2].col[3] == 0)
    @assert(pr.keys[2].col[4] == 1)
}

// countFittingPairs on parsed data
#test
{
    var pr = parse(SampleInput)
    defer parseFree(&pr)
    let count = countFittingPairs(&pr)
    @assert(count == 3'u64)
}

// Part 1: sample answer = 3
#test
{
    let result = solve(SampleInput)
    @assert(result.part1 == 3'u64)
}

// with &ptr (exercises with-pointer codegen)
#test
{
    var sr: SolveResult
    with &sr
    {
        .part1 = 42
    }
    @assert(sr.part1 == 42'u64)
}

// Inline retval struct return (exercises retval pattern)
struct HeightPair
{
    lock: Heights
    key:  Heights
    fit:  bool
}

#[Swag.Inline]
func makeHeightPair(lock: Heights, key: Heights) -> HeightPair
{
    var r: retval
    r.lock = lock
    r.key  = key
    r.fit  = lock.fits(key)
    return r
}

#test
{
    var lock: Heights
    lock.col[0] = 0; lock.col[1] = 0; lock.col[2] = 0; lock.col[3] = 0; lock.col[4] = 0
    var key: Heights
    key.col[0] = 5; key.col[1] = 5; key.col[2] = 5; key.col[3] = 5; key.col[4] = 5

    let pair = makeHeightPair(lock, key)
    @assert(pair.fit)
    @assert(pair.lock.eq(lock))
    @assert(pair.key.eq(key))
}

// Nested inline: makeHeightPair calls fits which is inline, which loops
#test
{
    var lock: Heights
    lock.col[0] = 5; lock.col[1] = 5; lock.col[2] = 5; lock.col[3] = 5; lock.col[4] = 5
    var key: Heights
    key.col[0] = 1; key.col[1] = 0; key.col[2] = 0; key.col[3] = 0; key.col[4] = 0

    let pair = makeHeightPair(lock, key)
    @assert(!pair.fit)
}

// parseInit/parseFree (exercises dynamic memory)
#test
{
    var pr = parseInit()
    @assert(pr.lockCount == 0'u32)
    @assert(pr.keyCount == 0'u32)
    parseFree(&pr)
}

// Single lock schematic
#test
{
    let single =
"""#####
.####
.####
.####
.#.#.
.#...
....."""
    var pr = parse(single)
    defer parseFree(&pr)
    @assert(pr.lockCount == 1'u32)
    @assert(pr.keyCount == 0'u32)
    @assert(pr.locks[0].col[0] == 0)
    @assert(pr.locks[0].col[1] == 5)
    @assert(pr.locks[0].col[2] == 3)
    @assert(pr.locks[0].col[3] == 4)
    @assert(pr.locks[0].col[4] == 3)
}

// Single key schematic
#test
{
    let single =
""".....
#....
#....
#...#
#.#.#
#.###
#####"""
    var pr = parse(single)
    defer parseFree(&pr)
    @assert(pr.lockCount == 0'u32)
    @assert(pr.keyCount == 1'u32)
    @assert(pr.keys[0].col[0] == 5)
    @assert(pr.keys[0].col[1] == 0)
    @assert(pr.keys[0].col[2] == 2)
    @assert(pr.keys[0].col[3] == 1)
    @assert(pr.keys[0].col[4] == 3)
}

// All zeros lock vs all zeros key: should fit
#test
{
    var lock: Heights
    var key: Heights
    @assert(lock.fits(key))
}

// Max height lock vs any key: overlap
#test
{
    var lock: Heights
    lock.col[0] = 5; lock.col[1] = 5; lock.col[2] = 5; lock.col[3] = 5; lock.col[4] = 5
    var key: Heights
    key.col[0] = 1; key.col[1] = 0; key.col[2] = 0; key.col[3] = 0; key.col[4] = 0
    @assert(!lock.fits(key))
}

// Boundary: exactly MaxHeight in each column → fits
#test
{
    var lock: Heights
    lock.col[0] = 3; lock.col[1] = 2; lock.col[2] = 1; lock.col[3] = 0; lock.col[4] = 5
    var key: Heights
    key.col[0] = 2; key.col[1] = 3; key.col[2] = 4; key.col[3] = 5; key.col[4] = 0
    // 3+2=5, 2+3=5, 1+4=5, 0+5=5, 5+0=5 → all exactly 5 → fits
    @assert(lock.fits(key))
}

// Boundary: one column at MaxHeight+1 → no fit
#test
{
    var lock: Heights
    lock.col[0] = 3; lock.col[1] = 2; lock.col[2] = 1; lock.col[3] = 1; lock.col[4] = 5
    var key: Heights
    key.col[0] = 2; key.col[1] = 3; key.col[2] = 4; key.col[3] = 5; key.col[4] = 0
    // col 3: 1+5=6 > 5 → overlap
    @assert(!lock.fits(key))
}

// Full solve
#test
{
    let result = solve(SampleInput)
    @assert(result.part1 == 3'u64)
}

// Pair-by-pair verification from puzzle description
#test
{
    var pr = parse(SampleInput)
    defer parseFree(&pr)

    // Lock 0 (0,5,3,4,3) vs Key 0 (5,0,2,1,3): overlap col4: 3+3=6
    @assert(!pr.locks[0].fits(pr.keys[0]))
    // Lock 0 vs Key 1 (4,3,4,0,2): overlap col1: 5+3=8
    @assert(!pr.locks[0].fits(pr.keys[1]))
    // Lock 0 vs Key 2 (3,0,2,0,1): fit
    @assert(pr.locks[0].fits(pr.keys[2]))
    // Lock 1 (1,2,0,5,3) vs Key 0: overlap col0: 1+5=6
    @assert(!pr.locks[1].fits(pr.keys[0]))
    // Lock 1 vs Key 1: fit
    @assert(pr.locks[1].fits(pr.keys[1]))
    // Lock 1 vs Key 2: fit
    @assert(pr.locks[1].fits(pr.keys[2]))
}

// for #reverse in key parsing (exercises reverse loop)
#test
{
    // Verify key parsing uses #reverse correctly
    let keyStr =
""".....
.....
.....
.....
.....
#.#.#
#####"""
    var pr = parse(keyStr)
    defer parseFree(&pr)
    @assert(pr.keyCount == 1'u32)
    // Only bottom 2 rows have '#' → heights should be 1 for cols 0,2,4
    @assert(pr.keys[0].col[0] == 1)
    @assert(pr.keys[0].col[1] == 0)
    @assert(pr.keys[0].col[2] == 1)
    @assert(pr.keys[0].col[3] == 0)
    @assert(pr.keys[0].col[4] == 1)
}

// Cast chain: u8 → u32 comparison in fits (exercises cast codegen)
#test
{
    var lock: Heights
    lock.col[0] = 4
    var key: Heights
    key.col[0] = 2
    // cast(u32) 4 + cast(u32) 2 = 6 > 5 → overlap
    @assert(!lock.fits(key))
    key.col[0] = 1
    // cast(u32) 4 + cast(u32) 1 = 5 ≤ 5 → fits
    @assert(lock.fits(key))
}
