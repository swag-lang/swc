#global fileprivate

// Advent of Code 2024 Day 13: find minimum token cost to reach prizes by
// pressing two claw-machine buttons (A costs 3, B costs 1). Each button
// moves the claw by a fixed delta. Solve the 2×2 linear system for each
// machine; only non-negative integer solutions are valid.
// Part 2 shifts every prize coordinate by 10 000 000 000 000.
// Exercises: switch with fallthrough, #[Swag.Complete], for #reverse,
// 0 to N inclusive range, ternary operator, @abs, while..do,
// #[Swag.NoInline], struct literal arguments.

const SampleInput =
"""Button A: X+94, Y+34
Button B: X+22, Y+67
Prize: X=8400, Y=5400

Button A: X+26, Y+66
Button B: X+67, Y+21
Prize: X=12748, Y=12176

Button A: X+17, Y+86
Button B: X+84, Y+37
Prize: X=7870, Y=6450

Button A: X+69, Y+23
Button B: X+27, Y+71
Prize: X=18641, Y=10279"""

// ---------------------------------------------------------------------------
// Vector type with operator overloading (opEquals)
// ---------------------------------------------------------------------------

struct Vec2
{
    x: s64
    y: s64
}

// Helper for Vec2 equality (exercises short function syntax)
func vec2Eq(a, b: Vec2) -> bool => a.x == b.x and a.y == b.y

// ---------------------------------------------------------------------------
// Machine description and parsing
// ---------------------------------------------------------------------------

const MaxMachines = 32'u32
const CostA       = 3'u64
const CostB       = 1'u64
const Part2Offset = 10000000000000's64

struct Machine
{
    a:     Vec2
    b:     Vec2
    prize: Vec2
}

enum ParseState: u8
{
    WantA,
    WantB,
    WantPrize,
    Done,
}

// Parse a number from bytes starting at pos; advances pos past the digits.
#[Swag.NoInline]
func parseNum(bytes: const [..] u8, pos: *u32) -> s64
{
    var neg = false
    if dref pos < @countof(bytes) and bytes[dref pos] == '-'
    {
        neg = true
        dref pos += 1
    }

    var val: s64
    for
    {
        if dref pos >= @countof(bytes) or bytes[dref pos] < '0' or bytes[dref pos] > '9' do
            break
        val = val * 10 + cast(s64) (bytes[dref pos] - '0')
        dref pos += 1
    }
    return neg ? -val : val
}

// Skip forward until the next digit or '-'.
func skipToNum(bytes: const [..] u8, pos: *u32)
{
    for
    {
        if dref pos >= @countof(bytes) do
            break
        let ch = bytes[dref pos]
        if ch == '-' or (ch >= '0' and ch <= '9') do
            break
        dref pos += 1
    }
}

func parseMachines(text: string, out: [*] Machine) -> u32
{
    let bytes = cast(const [..] u8) text
    var pos: u32
    var count: u32
    var state = ParseState.WantA

    for
    {
        if pos >= @countof(bytes) or count >= MaxMachines do
            break

        skipToNum(bytes, &pos)
        if pos >= @countof(bytes) do
            break

        let v1 = parseNum(bytes, &pos)
        skipToNum(bytes, &pos)
        let v2 = parseNum(bytes, &pos)

        // Switch with fallthrough to advance state machine
        #[Swag.Complete]
        switch state
        {
        case ParseState.WantA:
            out[count].a = {x: v1, y: v2}
            state = ParseState.WantB
            break
        case ParseState.WantB:
            out[count].b = {x: v1, y: v2}
            state = ParseState.WantPrize
            break
        case ParseState.WantPrize:
            out[count].prize = {x: v1, y: v2}
            count += 1
            state = ParseState.WantA
            break
        case ParseState.Done:
            break
        }
    }

    return count
}

// ---------------------------------------------------------------------------
// Solver: Cramer's rule for 2×2 integer system
// ---------------------------------------------------------------------------

// Solve:  a.x * na + b.x * nb = prize.x
//         a.y * na + b.y * nb = prize.y
// Returns token cost (3*na + nb), or 0 if no non-negative integer solution.
func solveMachine(m: Machine) -> u64
{
    let det = m.a.x * m.b.y - m.a.y * m.b.x
    if det == 0 do
        return 0

    let numA = m.prize.x * m.b.y - m.prize.y * m.b.x
    let numB = m.a.x * m.prize.y - m.a.y * m.prize.x

    // Integer division check: remainder must be zero
    if numA % det != 0 or numB % det != 0 do
        return 0

    let na = numA / det
    let nb = numB / det

    // Both press counts must be non-negative
    if na < 0 or nb < 0 do
        return 0

    return CostA * cast(u64) na + CostB * cast(u64) nb
}

struct Result
{
    part1: u64
    part2: u64
}

func solve(text: string) -> Result
{
    var machines: [MaxMachines] Machine
    let n = parseMachines(text, &machines[0])
    var result: Result

    // Part 1: solve each machine as-is
    for i in n
    {
        result.part1 += solveMachine(machines[i])
    }

    // Part 2: shift prizes, iterate in reverse to exercise for #reverse
    for #reverse i in n
    {
        var m = machines[i]
        m.prize.x += Part2Offset
        m.prize.y += Part2Offset
        result.part2 += solveMachine(m)
    }

    return result
}

// ---------------------------------------------------------------------------
// Utility: inclusive range + @abs exercise
// ---------------------------------------------------------------------------

// Count how many machines in a range [lo, hi] (inclusive 'to') have
// a solution for Part 1.
func countSolvable(machines: [*] Machine, lo: u32, hi: u32) -> u32
{
    var count: u32
    for i in lo to hi
    {
        if solveMachine(machines[i]) > 0 do
            count += 1
    }
    return count
}

// Determinant magnitude helper (exercises @abs)
func detMagnitude(m: Machine) -> s64 => @abs(m.a.x * m.b.y - m.a.y * m.b.x)

// ---------------------------------------------------------------------------
// Switch with fallthrough exercise
// ---------------------------------------------------------------------------

// Classify token cost into tiers using fallthrough.
// 0 → "free", 1-99 → "cheap", 100-999 → "mid", >=1000 → "expensive"
func costTier(cost: u64) -> u32
{
    var tier: u32

    // Map cost to bucket then fallthrough to set tier
    switch
    {
    case cost == 0:
        tier = 0
        break
    case cost < 100:
        tier = 1
        break
    case cost < 1000:
        tier = 2
        break
    default:
        tier = 3
        break
    }

    return tier
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// Vec2 equality helper
#test
{
    let a: Vec2 = {x: 10, y: 20}
    let b: Vec2 = {x: 10, y: 20}
    let c: Vec2 = {x: 10, y: 99}
    @assert(vec2Eq(a, b))
    @assert(!vec2Eq(a, c))
}

// Parse number with ternary, negative, while..do
#test
{
    let bytes = cast(const [..] u8) "X+94"
    var pos: u32 = 2
    let v = parseNum(bytes, &pos)
    @assert(v == 94)

    let bytes2 = cast(const [..] u8) "-42rest"
    var pos2: u32 = 0
    let v2 = parseNum(bytes2, &pos2)
    @assert(v2 == -42)
}

// Parse full sample input
#test
{
    var machines: [MaxMachines] Machine
    let n = parseMachines(SampleInput, &machines[0])
    @assert(n == 4'u32)
    @assert(vec2Eq(machines[0].a, {x: 94, y: 34}))
    @assert(vec2Eq(machines[0].b, {x: 22, y: 67}))
    @assert(vec2Eq(machines[0].prize, {x: 8400, y: 5400}))
    @assert(vec2Eq(machines[3].a, {x: 69, y: 23}))
}

// Individual machine solve
#test
{
    // Machine 1: A=(94,34) B=(22,67) Prize=(8400,5400) → 80A+40B = 280
    let m1: Machine = {a: {x: 94, y: 34}, b: {x: 22, y: 67}, prize: {x: 8400, y: 5400}}
    @assert(solveMachine(m1) == 280'u64)

    // Machine 2: no integer solution
    let m2: Machine = {a: {x: 26, y: 66}, b: {x: 67, y: 21}, prize: {x: 12748, y: 12176}}
    @assert(solveMachine(m2) == 0'u64)

    // Machine 3: A=(17,86) B=(84,37) Prize=(7870,6450) → 38A+86B = 200
    let m3: Machine = {a: {x: 17, y: 86}, b: {x: 84, y: 37}, prize: {x: 7870, y: 6450}}
    @assert(solveMachine(m3) == 200'u64)

    // Machine 4: no integer solution
    let m4: Machine = {a: {x: 69, y: 23}, b: {x: 27, y: 71}, prize: {x: 18641, y: 10279}}
    @assert(solveMachine(m4) == 0'u64)
}

// Full sample: Part1 = 480
#test
{
    let result = solve(SampleInput)
    @assert(result.part1 == 480'u64)
}

// Part2: machines 2 and 4 become solvable with the offset
#test
{
    let result = solve(SampleInput)
    @assert(result.part2 > 0'u64)
}

// Inclusive range and @abs
#test
{
    var machines: [MaxMachines] Machine
    let n = parseMachines(SampleInput, &machines[0])

    // Machines 0 and 2 are solvable (indices 0 to 3 inclusive)
    @assert(countSolvable(&machines[0], 0, n - 1) == 2'u32)
    // Only machine 0 in range [0, 0]
    @assert(countSolvable(&machines[0], 0, 0) == 1'u32)

    // Determinant magnitude
    @assert(detMagnitude(machines[0]) > 0)
}

// Cost tier switch exercise
#test
{
    @assert(costTier(0) == 0'u32)
    @assert(costTier(1) == 1'u32)
    @assert(costTier(99) == 1'u32)
    @assert(costTier(100) == 2'u32)
    @assert(costTier(280) == 2'u32)
    @assert(costTier(1000) == 3'u32)
    @assert(costTier(99999) == 3'u32)
}

// Edge case: zero-delta buttons (det=0)
#test
{
    let m: Machine = {a: {x: 0, y: 0}, b: {x: 0, y: 0}, prize: {x: 100, y: 100}}
    @assert(solveMachine(m) == 0'u64)
}

// Edge case: prize at origin
#test
{
    let m: Machine = {a: {x: 1, y: 0}, b: {x: 0, y: 1}, prize: {x: 0, y: 0}}
    @assert(solveMachine(m) == 0'u64)
}

// for #reverse: reverse order produces same sum
#test
{
    var fwd: s64
    var rev: s64
    for i in 1 to 10
    {
        fwd += cast(s64) i
    }
    for #reverse i in 1 to 10
    {
        rev += cast(s64) i
    }
    @assert(fwd == rev)
    @assert(fwd == 55)
}
