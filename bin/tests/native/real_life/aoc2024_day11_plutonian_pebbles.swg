#global fileprivate

// Advent of Code 2024 Day 11: stones with numbers transform each "blink".
// If 0 → becomes 1. If even digits → splits into two halves. Otherwise × 2024.
// Part 1: count stones after 25 blinks. Part 2: after 75 blinks.
// Exercises: retval, #run compile-time, closures, orelse,
// heap allocation, explicit cleanup, typed variadic.

const SampleInput = "125 17"
const TinyInput   = "0 1 10 99 999"
const SingleInput = "0"

// ---------------------------------------------------------------------------
// Compile-time: precompute powers of 10 via #run
// ---------------------------------------------------------------------------

const MaxPow = 20'u32

func buildPow10()->[MaxPow] u64
{
    var result: retval
    result[0] = 1
    for i in 1 until MaxPow
    {
        result[i] = result[i - 1] * 10
    }
    return result
}

const Pow10 = #run buildPow10()
#assert(Pow10[0] == 1)
#assert(Pow10[3] == 1000)
#assert(Pow10[6] == 1000000)

// ---------------------------------------------------------------------------
// Digit helpers
// ---------------------------------------------------------------------------

func digitCount(n: u64)->u32
{
    for i in 1 until MaxPow
    {
        if n < Pow10[i] do
            return cast(u32) i
    }
    return 1
}

struct SplitResult
{
    left:  u64
    right: u64
}

func splitHalf(n: u64, digits: u32)->SplitResult
{
    let div = Pow10[digits / 2]
    return {left: n / div, right: n % div}
}

// ---------------------------------------------------------------------------
// StoneMap: open-addressing hash map (stone value → count)
// ---------------------------------------------------------------------------

const MapCap = 4096'u32

struct StoneMap
{
    keys:   [*] u64
    counts: [*] u64
    alive:  [*] bool
    used:   u32
}

func mapInit()->StoneMap
{
    var result: retval
    result.keys   = cast([*] u64)  @alloc(cast(u64) MapCap * #sizeof(u64))
    result.counts = cast([*] u64)  @alloc(cast(u64) MapCap * #sizeof(u64))
    result.alive  = cast([*] bool) @alloc(cast(u64) MapCap * #sizeof(bool))
    result.used = 0
    for i in MapCap
    {
        result.alive[i] = false
        result.counts[i] = 0
    }
    return result
}

func mapFree(m: *StoneMap)
{
    if m.keys   do @free(m.keys)
    if m.counts do @free(m.counts)
    if m.alive  do @free(m.alive)
}

func mapIsEmpty(m: *StoneMap)->bool
{
    return m.used == 0
}

func mapProbe(m: *StoneMap, key: u64)->u32
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

// Lookup returning a nullable pointer — enables orelse
func mapLookup(m: *StoneMap, key: u64)->*u64
{
    let idx = mapProbe(m, key)
    if m.alive[idx] and m.keys[idx] == key do
        return &m.counts[idx]
    return null
}

func mapAdd(m: *StoneMap, key: u64, count: u64)
{
    let idx = mapProbe(m, key)
    if m.alive[idx] and m.keys[idx] == key
    {
        m.counts[idx] += count
        return
    }
    m.keys[idx]   = key
    m.counts[idx]  = count
    m.alive[idx]   = true
    m.used += 1
}

func mapClear(m: *StoneMap)
{
    for MapCap
    {
        m.alive[@index] = false
        m.counts[@index] = 0
    }
    m.used = 0
}

func mapTotal(m: *StoneMap)->u64
{
    var total: u64
    for i in MapCap
    {
        if m.alive[i] do
            total += m.counts[i]
    }
    return total
}

// ---------------------------------------------------------------------------
// Closure-based iteration: visit each (key, count) pair
// ---------------------------------------------------------------------------

alias StoneVisitor = func||(u64, u64)

func forEachStone(m: *StoneMap, cb: StoneVisitor)
{
    for i in MapCap
    {
        if m.alive[i] do
            cb(m.keys[i], m.counts[i])
    }
}

// ---------------------------------------------------------------------------
// Blink simulation
// ---------------------------------------------------------------------------

const Multiplier = 2024'u64

func blinkStone(stone: u64, count: u64, dst: *StoneMap)
{
    if stone == 0
    {
        mapAdd(dst, 1, count)
        return
    }

    let digs = digitCount(stone)
    if digs % 2 == 0
    {
        let half = splitHalf(stone, digs)
        mapAdd(dst, half.left, count)
        mapAdd(dst, half.right, count)
        return
    }

    mapAdd(dst, stone * Multiplier, count)
}

func blinkOnce(src: *StoneMap, dst: *StoneMap)
{
    mapClear(dst)
    for i in MapCap
    {
        if src.alive[i] do
            blinkStone(src.keys[i], src.counts[i], dst)
    }
}

// ---------------------------------------------------------------------------
// Parsing: typed variadic for fixed-size initialisation
// ---------------------------------------------------------------------------

func mapFromValues(values: u64...)->StoneMap
{
    var result: retval = mapInit()
    foreach v in values
    {
        mapAdd(&result, v, 1)
    }
    return result
}

func parseInput(text: string)->StoneMap
{
    var result: retval = mapInit()
    let bytes = cast(const [..] u8) text
    var acc: u64
    var inNum = false

    for @countof(bytes)
    {
        let ch = bytes[@index]
        if ch >= '0' and ch <= '9'
        {
            acc = acc * 10 + cast(u64) (ch - '0')
            inNum = true
        }
        elif inNum
        {
            mapAdd(&result, acc, 1)
            acc = 0
            inNum = false
        }
    }

    if inNum do
        mapAdd(&result, acc, 1)
    return result
}

// ---------------------------------------------------------------------------
// Solver
// ---------------------------------------------------------------------------

struct BlinkResult
{
    after6:  u64
    after25: u64
    after75: u64
}

func currentMap(a: *StoneMap, b: *StoneMap, step: u32)->*StoneMap
{
    if step % 2 == 0 do
        return a
    return b
}

func solve(text: string)->BlinkResult
{
    var a = parseInput(text)
    var b = mapInit()
    var result: retval

    for i in 75
    {
        let cur = currentMap(&a, &b, cast(u32) i)
        if i == 6  do result.after6  = mapTotal(cur)
        if i == 25 do result.after25 = mapTotal(cur)

        if i % 2 == 0
        {
            blinkOnce(&a, &b)
        }
        else
        {
            blinkOnce(&b, &a)
        }
    }

    let final = currentMap(&a, &b, 75)
    result.after75 = mapTotal(final)
    mapFree(&a)
    mapFree(&b)
    return result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// Test compile-time power table
#test
{
    @assert(Pow10[0] == 1'u64)
    @assert(Pow10[1] == 10'u64)
    @assert(Pow10[9] == 1000000000'u64)
}

// Test digit counting
#test
{
    @assert(digitCount(0) == 1'u32)
    @assert(digitCount(1) == 1'u32)
    @assert(digitCount(9) == 1'u32)
    @assert(digitCount(10) == 2'u32)
    @assert(digitCount(99) == 2'u32)
    @assert(digitCount(100) == 3'u32)
    @assert(digitCount(1000) == 4'u32)
    @assert(digitCount(123456) == 6'u32)
}

// Test split
#test
{
    let s = splitHalf(1234, 4)
    @assert(s.left == 12'u64)
    @assert(s.right == 34'u64)
    let s2 = splitHalf(1000, 4)
    @assert(s2.left == 10'u64)
    @assert(s2.right == 0'u64)
}

// Test StoneMap basics and orelse
#test
{
    var m = mapInit()
    @assert(mapIsEmpty(&m))

    mapAdd(&m, 42, 5)
    @assert(!mapIsEmpty(&m))

    var zero: u64 = 0
    let p = mapLookup(&m, 42) orelse &zero
    @assert(dref p == 5'u64)

    let q = mapLookup(&m, 999) orelse &zero
    @assert(dref q == 0'u64)

    mapAdd(&m, 42, 3)
    let r = mapLookup(&m, 42) orelse &zero
    @assert(dref r == 8'u64)

    @assert(mapTotal(&m) == 8'u64)
    mapFree(&m)
}

// Test typed variadic constructor
#test
{
    var m = mapFromValues(0'u64, 1, 10, 99, 999)
    @assert(mapTotal(&m) == 5'u64)
    var zero: u64 = 0
    @assert(dref (mapLookup(&m, 0) orelse &zero) == 1'u64)
    @assert(dref (mapLookup(&m, 10) orelse &zero) == 1'u64)
    mapFree(&m)
}

// Test closure-based iteration
#test
{
    var m = mapInit()
    mapAdd(&m, 10, 2)
    mapAdd(&m, 20, 3)

    var sum: u64 = 0
    let pSum = &sum
    let cb: StoneVisitor = func|pSum|(key: u64, count: u64)
    {
        dref pSum += key * count
    }
    forEachStone(&m, cb)
    @assert(sum == 80'u64)
    mapFree(&m)
}

// Test single blink: 0 → 1
#test
{
    var a = mapInit()
    mapAdd(&a, 0, 1)
    var b = mapInit()
    blinkOnce(&a, &b)
    var zero: u64 = 0
    @assert(dref (mapLookup(&b, 1) orelse &zero) == 1'u64)
    @assert(mapTotal(&b) == 1'u64)
    mapFree(&a)
    mapFree(&b)
}

// Test single blink: even digits → split
#test
{
    var a = mapInit()
    mapAdd(&a, 1234, 1)
    @assert(mapTotal(&a) == 1'u64)

    var b = mapInit()
    blinkOnce(&a, &b)
    @assert(mapTotal(&b) == 2'u64)

    var zero: u64 = 0
    let p12 = mapLookup(&b, 12)
    let p34 = mapLookup(&b, 34)
    @assert(p12 != null)
    @assert(p34 != null)
    @assert(dref (p12 orelse &zero) == 1'u64)
    @assert(dref (p34 orelse &zero) == 1'u64)
    mapFree(&a)
    mapFree(&b)
}

// Test single blink: odd digits → multiply by 2024
#test
{
    var a = mapInit()
    mapAdd(&a, 125, 1)
    var b = mapInit()
    blinkOnce(&a, &b)
    var zero: u64 = 0
    @assert(dref (mapLookup(&b, 253000) orelse &zero) == 1'u64)
    mapFree(&a)
    mapFree(&b)
}

// Test sample input after 6 and 25 blinks
#test
{
    let result = solve(SampleInput)
    @assert(result.after6 == 22'u64)
    @assert(result.after25 == 55312'u64)
}

// Test single zero stone
#test
{
    let result = solve(SingleInput)
    @assert(result.after6 > 0'u64)
}

// Test map clear
#test
{
    var m = mapInit()
    mapAdd(&m, 1, 10)
    mapAdd(&m, 2, 20)
    @assert(mapTotal(&m) == 30'u64)
    mapClear(&m)
    @assert(mapIsEmpty(&m))
    @assert(mapTotal(&m) == 0'u64)
    mapFree(&m)
}
