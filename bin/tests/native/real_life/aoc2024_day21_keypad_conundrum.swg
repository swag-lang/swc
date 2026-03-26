#global fileprivate

// Advent of Code 2024 Day 21: control a chain of robots pressing keypads.
// Part 1: 2 directional robots between you and the numeric keypad.
// Part 2: 25 directional robots.
// Exercises: #run compile-time tables, switch inside #[Swag.Inline],
// memoisation with open-addressing hash map, with blocks, recursive DP.

const SampleInput =
"""029A
980A
179A
456A
379A"""

// ---------------------------------------------------------------------------
// Keypad positions (compile-time)
// ---------------------------------------------------------------------------

// Numeric keypad:   789 / 456 / 123 / _0A
// Directional:      _^A / <v>

struct Coord
{
    r: s32
    c: s32
}

// Build numeric keypad coordinate table at compile time
func buildNumPad() -> [11] Coord
{
    var result: retval
    // 0-9 map to indices 0-9, A maps to index 10
    result[7] = Coord{r: 0, c: 0}
    result[8] = Coord{r: 0, c: 1}
    result[9] = Coord{r: 0, c: 2}
    result[4] = Coord{r: 1, c: 0}
    result[5] = Coord{r: 1, c: 1}
    result[6] = Coord{r: 1, c: 2}
    result[1] = Coord{r: 2, c: 0}
    result[2] = Coord{r: 2, c: 1}
    result[3] = Coord{r: 2, c: 2}
    result[0] = Coord{r: 3, c: 1}
    result[10] = Coord{r: 3, c: 2}  // A
    return result
}

const NumPad = #run buildNumPad()
const NumGapR: s32 = 3  // gap at (3,0)
const NumGapC: s32 = 0

// Directional keypad: _^A / <v>
// Index: 0=^, 1=A, 2=<, 3=v, 4=>
func buildDirPad() -> [5] Coord
{
    var result: retval
    result[0] = Coord{r: 0, c: 1}  // ^
    result[1] = Coord{r: 0, c: 2}  // A
    result[2] = Coord{r: 1, c: 0}  // <
    result[3] = Coord{r: 1, c: 1}  // v
    result[4] = Coord{r: 1, c: 2}  // >
    return result
}

const DirPad = #run buildDirPad()
const DirGapR: s32 = 0  // gap at (0,0)
const DirGapC: s32 = 0

// Map direction move to directional key index
// Switch inside inline exercises switch codegen in inline context
#[Swag.Inline]
func dirKeyIdx(dr: s32, dc: s32) -> u32
{
    if dr < 0 do return 0  // ^
    if dr > 0 do return 3  // v
    if dc < 0 do return 2  // <
    return 4                // >
}

// ---------------------------------------------------------------------------
// Memoisation hash map (key: packed state, value: u64 cost)
// ---------------------------------------------------------------------------

const MapCap = 16384'u32

struct Memo
{
    keys:   [*] u64
    vals:   [*] u64
    alive:  [*] bool
    used:   u32
}

func memoInit() -> Memo
{
    var m: Memo
    m.keys  = cast([*] u64)  @alloc(cast(u64) MapCap * #sizeof(u64))
    m.vals  = cast([*] u64)  @alloc(cast(u64) MapCap * #sizeof(u64))
    m.alive = cast([*] bool) @alloc(cast(u64) MapCap * #sizeof(bool))
    for MapCap { m.alive[@index] = false }
    return m
}

func memoFree(m: *Memo)
{
    if m.keys  do @free(m.keys)
    if m.vals  do @free(m.vals)
    if m.alive do @free(m.alive)
}

func memoProbe(m: *Memo, key: u64) -> u32
{
    var h = key ^ (key >> 16)
    h *= 0x45d9f3b
    h ^= h >> 16
    var idx = cast(u32) (h % cast(u64) MapCap)
    for MapCap
    {
        if !m.alive[idx] or m.keys[idx] == key do
            return idx
        idx = (idx + 1) % MapCap
    }
    @assert(false)
    return 0
}

func memoGet(m: *Memo, key: u64, found: *bool) -> u64
{
    let idx = memoProbe(m, key)
    if m.alive[idx] and m.keys[idx] == key
    {
        dref found = true
        return m.vals[idx]
    }
    dref found = false
    return 0
}

func memoPut(m: *Memo, key: u64, val: u64)
{
    let idx = memoProbe(m, key)
    m.keys[idx]  = key
    m.vals[idx]  = val
    m.alive[idx] = true
}

// ---------------------------------------------------------------------------
// Core DP: cost to move between two keys at a given depth
// ---------------------------------------------------------------------------

// Pack (fromIdx, toIdx, depth, isNumPad) into a u64 key
#[Swag.Inline]
func packKey(fromIdx: u32, dstIdx: u32, depth: u32, isNum: bool) -> u64
{
    return cast(u64) fromIdx | (cast(u64) dstIdx << 8) | (cast(u64) depth << 16) | (cast(u64) (isNum ? 1'u32 : 0'u32) << 24)
}

// Recursive cost: minimal human presses to go from key `from` to key `to`
// and press `to`, at `depth` levels of directional robots remaining.
// isNum = true for first robot (numeric pad), false for directional pad.
func moveCost(from: u32, dst: u32, depth: u32, isNum: bool, memo: *Memo) -> u64
{
    let key = packKey(from, dst, depth, isNum)
    var found: bool
    let cached = memoGet(memo, key, &found)
    if found do return cached

    var fromCoord: Coord
    var toCoord: Coord
    var gapR: s32
    var gapC: s32

    if isNum
    {
        fromCoord = NumPad[from]
        toCoord   = NumPad[dst]
        gapR = NumGapR
        gapC = NumGapC
    }
    else
    {
        fromCoord = DirPad[from]
        toCoord   = DirPad[dst]
        gapR = DirGapR
        gapC = DirGapC
    }

    let dr = toCoord.r - fromCoord.r
    let dc = toCoord.c - fromCoord.c

    // At depth 0, the human directly presses: just manhattan + 1 (for 'A')
    if depth == 0
    {
        let cost = cast(u64) (@abs(dr) + @abs(dc)) + 1
        memoPut(memo, key, cost)
        return cost
    }

    // Build the sequence of directional moves, try both orderings
    // (horizontal-first vs vertical-first), pick minimum cost.
    // Each ordering is only valid if it doesn't cross the gap.

    var bestCost: u64 = 0xFFFFFFFFFFFFFFFF'u64

    // Try horizontal then vertical
    let hfValid = !(fromCoord.r == gapR and toCoord.c == gapC)
    if hfValid
    {
        var cost: u64
        var cur: u32 = 1  // start at 'A' on directional pad

        // Horizontal moves
        var hSteps = cast(u32) @abs(dc)
        if dc != 0
        {
            let hKey = dirKeyIdx(0, dc)
            for hSteps
            {
                cost += moveCost(cur, hKey, depth - 1, false, memo)
                cur = hKey
            }
        }

        // Vertical moves
        var vSteps = cast(u32) @abs(dr)
        if dr != 0
        {
            let vKey = dirKeyIdx(dr, 0)
            for vSteps
            {
                cost += moveCost(cur, vKey, depth - 1, false, memo)
                cur = vKey
            }
        }

        // Press A
        cost += moveCost(cur, 1, depth - 1, false, memo)
        if cost < bestCost do bestCost = cost
    }

    // Try vertical then horizontal
    let vfValid = !(toCoord.r == gapR and fromCoord.c == gapC)
    if vfValid
    {
        var cost: u64
        var cur: u32 = 1  // start at 'A'

        // Vertical moves
        var vSteps = cast(u32) @abs(dr)
        if dr != 0
        {
            let vKey = dirKeyIdx(dr, 0)
            for vSteps
            {
                cost += moveCost(cur, vKey, depth - 1, false, memo)
                cur = vKey
            }
        }

        // Horizontal moves
        var hSteps = cast(u32) @abs(dc)
        if dc != 0
        {
            let hKey = dirKeyIdx(0, dc)
            for hSteps
            {
                cost += moveCost(cur, hKey, depth - 1, false, memo)
                cur = hKey
            }
        }

        // Press A
        cost += moveCost(cur, 1, depth - 1, false, memo)
        if cost < bestCost do bestCost = cost
    }

    memoPut(memo, key, bestCost)
    return bestCost
}

// ---------------------------------------------------------------------------
// Parsing and solving
// ---------------------------------------------------------------------------

// Map a character to numeric keypad index
func charToNumIdx(ch: u8) -> u32
{
    if ch >= '0' and ch <= '9' do
        return cast(u32) (ch - '0')
    return 10  // 'A'
}

// Extract numeric value from a code (e.g. "029A" → 29)
func codeNumericValue(code: const [..] u8, codeLen: u32) -> u64
{
    var val: u64
    for i in codeLen
    {
        let ch = code[i]
        if ch >= '0' and ch <= '9'
        {
            val = val * 10 + cast(u64) (ch - '0')
        }
    }
    return val
}

func solveCode(code: const [..] u8, codeLen: u32, depth: u32, memo: *Memo) -> u64
{
    var totalCost: u64
    var cur: u32 = 10  // start at 'A' on numeric pad

    for i in codeLen
    {
        let target = charToNumIdx(code[i])
        totalCost += moveCost(cur, target, depth, true, memo)
        cur = target
    }

    return totalCost
}

struct SolveResult
{
    part1: u64
    part2: u64
}

func solve(text: string) -> SolveResult
{
    var memo = memoInit()
    defer memoFree(&memo)

    var result: SolveResult
    let bytes = cast(const [..] u8) text
    var pos: u32

    for
    {
        if pos >= @countof(bytes) do break

        // Skip newlines
        for
        {
            if pos >= @countof(bytes) do break
            if bytes[pos] != '\n' and bytes[pos] != '\r' do break
            pos += 1
        }
        if pos >= @countof(bytes) do break

        // Read code
        let codeStart = pos
        for
        {
            if pos >= @countof(bytes) do break
            if bytes[pos] == '\n' or bytes[pos] == '\r' do break
            pos += 1
        }

        let codeLen = pos - codeStart
        if codeLen == 0 do continue

        let codeSlice = @mkslice(&bytes[codeStart], cast(u64) codeLen)
        let numVal = codeNumericValue(codeSlice, codeLen)

        let cost1 = solveCode(codeSlice, codeLen, 2, &memo)
        result.part1 += cost1 * numVal

        let cost2 = solveCode(codeSlice, codeLen, 25, &memo)
        result.part2 += cost2 * numVal
    }

    return result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// Compile-time table verification
#test
{
    // '7' is at (0,0)
    @assert(NumPad[7].r == 0)
    @assert(NumPad[7].c == 0)
    // 'A' is at (3,2)
    @assert(NumPad[10].r == 3)
    @assert(NumPad[10].c == 2)
    // '0' is at (3,1)
    @assert(NumPad[0].r == 3)
    @assert(NumPad[0].c == 1)
}

// Directional pad
#test
{
    // '^' at (0,1)
    @assert(DirPad[0].r == 0)
    @assert(DirPad[0].c == 1)
    // 'A' at (0,2)
    @assert(DirPad[1].r == 0)
    @assert(DirPad[1].c == 2)
    // '<' at (1,0)
    @assert(DirPad[2].r == 1)
    @assert(DirPad[2].c == 0)
}

// dirKeyIdx inline
#test
{
    @assert(dirKeyIdx(-1, 0) == 0'u32)  // ^
    @assert(dirKeyIdx(1, 0) == 3'u32)   // v
    @assert(dirKeyIdx(0, -1) == 2'u32)  // <
    @assert(dirKeyIdx(0, 1) == 4'u32)   // >
}

// packKey inline
#test
{
    let k1 = packKey(0, 1, 2, true)
    let k2 = packKey(0, 1, 2, false)
    @assert(k1 != k2)
    let k3 = packKey(1, 0, 2, true)
    @assert(k1 != k3)
}

// Memo basics
#test
{
    var m = memoInit()
    defer memoFree(&m)

    var found: bool
    discard memoGet(&m, 42, &found)
    @assert(!found)

    memoPut(&m, 42, 100)
    let v = memoGet(&m, 42, &found)
    @assert(found)
    @assert(v == 100'u64)
}

// charToNumIdx
#test
{
    @assert(charToNumIdx('0') == 0'u32)
    @assert(charToNumIdx('9') == 9'u32)
    @assert(charToNumIdx('A') == 10'u32)
}

// codeNumericValue
#test
{
    var buf: [4] u8
    buf[0] = '0'; buf[1] = '2'; buf[2] = '9'; buf[3] = 'A'
    let sl = @mkslice(&buf[0], 4'u64)
    @assert(codeNumericValue(sl, 4) == 29'u64)
}

// Depth 0: direct presses, manhattan + 1
#test
{
    var m = memoInit()
    defer memoFree(&m)
    // A(10) to 0(0): A at (3,2), 0 at (3,1) → manhattan 1 + press = 2
    let c = moveCost(10, 0, 0, true, &m)
    @assert(c == 2'u64)
}

// Sample Part 1 = 126384
#test
{
    let result = solve(SampleInput)
    @assert(result.part1 == 126384'u64)
}

// Single code "029A" at depth 2 = 68 presses
#test
{
    var m = memoInit()
    defer memoFree(&m)
    var buf: [4] u8
    buf[0] = '0'; buf[1] = '2'; buf[2] = '9'; buf[3] = 'A'
    let sl = @mkslice(&buf[0], 4'u64)
    let cost = solveCode(sl, 4, 2, &m)
    @assert(cost == 68'u64)
}

// Part 2 is computed but no sample answer given — just verify it runs
#test
{
    let result = solve(SampleInput)
    @assert(result.part2 > 0'u64)
}

// with &ptr: exercises the fix for with-pointer codegen crash
#test
{
    var c: Coord
    with &c
    {
        .r = 5
        .c = 10
    }
    @assert(c.r == 5)
    @assert(c.c == 10)
}
