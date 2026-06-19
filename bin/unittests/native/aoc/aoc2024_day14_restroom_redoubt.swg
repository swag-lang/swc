#global fileprivate

// Advent of Code 2024 Day 14: robots on a toroidal grid move with constant
// velocity. Part 1: multiply quadrant populations after 100 steps.
// Part 2: find the first step where robots cluster tightly (Christmas tree).
// Exercises: with blocks, cast() auto-inference, compound assignment (*=,
// <<=), @countof on fixed arrays, const arithmetic, #[Swag.Mixin].

const SampleInput =
"""p=0,4 v=3,-3
p=6,3 v=-1,-3
p=10,3 v=-1,2
p=2,0 v=2,-1
p=0,0 v=1,3
p=3,0 v=-2,-2
p=7,6 v=-1,-3
p=3,0 v=-1,-2
p=9,3 v=2,3
p=7,3 v=-1,2
p=2,4 v=2,-3
p=9,5 v=-3,-3"""

// ---------------------------------------------------------------------------
// Constants via const arithmetic
// ---------------------------------------------------------------------------

const MaxRobots    = 512'u32
const SampleWidth  = 11's32
const SampleHeight = 7's32
const Steps        = 100'u32

// Quadrant indices computed at compile time
const QuadTL = 0'u32
const QuadTR = 1'u32
const QuadBL = 2'u32
const QuadBR = 3'u32
const NumQuads = QuadBR + 1
#assert(NumQuads == 4)

// ---------------------------------------------------------------------------
// Robot struct and parsing
// ---------------------------------------------------------------------------

struct Robot
{
    px: s32
    py: s32
    vx: s32
    vy: s32
}

struct Fleet
{
    bots:  [MaxRobots] Robot
    count: u32
    w:     s32
    h:     s32
}

func parseS32(bytes: const [..] u8, pos: *u32) -> s32
{
    var neg = false
    if dref pos < @countof(bytes) and bytes[dref pos] == '-'
    {
        neg = true
        dref pos += 1
    }

    var val: s32
    for
    {
        if dref pos >= @countof(bytes) do
            break
        let ch = bytes[dref pos]
        if ch < '0' or ch > '9' do
            break
        val = val * 10 + cast(s32) (ch - '0')
        dref pos += 1
    }

    return neg ? -val : val
}

func skipToDigitOrMinus(bytes: const [..] u8, pos: *u32)
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

func parseFleet(text: string, w, h: s32) -> Fleet
{
    var fleet: Fleet
    fleet.w = w
    fleet.h = h
    let bytes = cast(const [..] u8) text

    var pos: u32
    for
    {
        if pos >= @countof(bytes) or fleet.count >= MaxRobots do
            break

        skipToDigitOrMinus(bytes, &pos)
        if pos >= @countof(bytes) do
            break

        let px = parseS32(bytes, &pos)
        skipToDigitOrMinus(bytes, &pos)
        let py = parseS32(bytes, &pos)
        skipToDigitOrMinus(bytes, &pos)
        let vx = parseS32(bytes, &pos)
        skipToDigitOrMinus(bytes, &pos)
        let vy = parseS32(bytes, &pos)

        // Use 'with' block to populate the robot
        with fleet.bots[fleet.count]
        {
            .px = px
            .py = py
            .vx = vx
            .vy = vy
        }
        fleet.count += 1
    }

    return fleet
}

// ---------------------------------------------------------------------------
// Simulation
// ---------------------------------------------------------------------------

// Positive modulo (Swag % can return negative for negative dividend)
func posMod(a, m: s32) -> s32
{
    let r = a % m
    return r < 0 ? r + m : r
}

// Advance one robot by n steps on a toroidal grid.
func advanceRobot(bot: Robot, n: s32, w, h: s32) -> Robot
{
    var result: Robot
    result.vx = bot.vx
    result.vy = bot.vy
    result.px = posMod(bot.px + bot.vx * n, w)
    result.py = posMod(bot.py + bot.vy * n, h)
    return result
}

// ---------------------------------------------------------------------------
// Part 1: quadrant safety factor
// ---------------------------------------------------------------------------

func safetyFactor(fleet: *Fleet, steps: u32) -> u64
{
    let midX = fleet.w / 2
    let midY = fleet.h / 2
    var quads: [NumQuads] u32

    for i in fleet.count
    {
        let bot = advanceRobot(fleet.bots[i], cast(s32) steps, fleet.w, fleet.h)

        // Skip robots exactly on the midlines
        if bot.px == midX or bot.py == midY do
            continue

        // Determine quadrant with cast() auto-inference
        let right: bool = cast() (bot.px > midX)
        let bottom: bool = cast() (bot.py > midY)

        if !right and !bottom do quads[QuadTL] += 1
        if right  and !bottom do quads[QuadTR] += 1
        if !right and bottom  do quads[QuadBL] += 1
        if right  and bottom  do quads[QuadBR] += 1
    }

    // Multiply quadrant counts using compound assignment (*=)
    var result: u64 = 1
    for q in NumQuads
    {
        result *= cast(u64) quads[q]
    }
    return result
}

// ---------------------------------------------------------------------------
// Part 2: find clustering step (Christmas tree)
// ---------------------------------------------------------------------------

// Mixin: compute variance of one coordinate axis.
// Expects caller to have: fleet (*Fleet), step (s32), w/h (s32).
// Injects: axisVariance (u64).
#[Swag.Mixin]
func computeVarianceX(fleet: *Fleet, step: s32)
{
    var sumX: s64
    var sumX2: s64
    for i in fleet.count
    {
        let bot = advanceRobot(fleet.bots[i], step, fleet.w, fleet.h)
        sumX  += cast(s64) bot.px
        sumX2 += cast(s64) bot.px * cast(s64) bot.px
    }
    let n    = cast(s64) fleet.count
    let mean = sumX / n
    axisVariance = cast(u64) (sumX2 / n - mean * mean)
}

// Find the step (up to maxSteps) with minimum X-axis variance —
// a proxy for tight horizontal clustering (the tree shape).
func findClusterStep(fleet: *Fleet, maxSteps: u32) -> u32
{
    var bestStep: u32
    var bestVar: u64 = 0xFFFFFFFFFFFFFFFF

    for s in maxSteps
    {
        var axisVariance: u64
        computeVarianceX(fleet, cast(s32) s)
        if axisVariance < bestVar
        {
            bestVar  = axisVariance
            bestStep = cast(u32) s
        }
    }

    return bestStep
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// Const arithmetic
#test
{
    @assert(NumQuads == 4'u32)
    @assert(QuadBR == 3'u32)
}

// Positive modulo
#test
{
    @assert(posMod(7, 5) == 2)
    @assert(posMod(-1, 5) == 4)
    @assert(posMod(-3, 11) == 8)
    @assert(posMod(0, 7) == 0)
    @assert(posMod(11, 11) == 0)
}

// Parse fleet with 'with' blocks
#test
{
    let fleet = parseFleet(SampleInput, SampleWidth, SampleHeight)
    @assert(fleet.count == 12'u32)
    @assert(fleet.w == 11)
    @assert(fleet.h == 7)

    // First robot: p=0,4 v=3,-3
    @assert(fleet.bots[0].px == 0)
    @assert(fleet.bots[0].py == 4)
    @assert(fleet.bots[0].vx == 3)
    @assert(fleet.bots[0].vy == -3)

    // Last robot: p=9,5 v=-3,-3
    @assert(fleet.bots[11].px == 9)
    @assert(fleet.bots[11].py == 5)
    @assert(fleet.bots[11].vx == -3)
    @assert(fleet.bots[11].vy == -3)
}

// Single robot advance
#test
{
    let bot: Robot = {px: 2, py: 4, vx: 2, vy: -3}
    let b1 = advanceRobot(bot, 1, SampleWidth, SampleHeight)
    @assert(b1.px == 4)
    @assert(b1.py == 1)

    let b5 = advanceRobot(bot, 5, SampleWidth, SampleHeight)
    @assert(b5.px == 1)
    @assert(b5.py == 3)
}

// @countof on fixed array
#test
{
    var quads: [NumQuads] u32
    @assert(@countof(quads) == 4)
}

// Safety factor for sample: expected 12
#test
{
    var fleet = parseFleet(SampleInput, SampleWidth, SampleHeight)
    let sf = safetyFactor(&fleet, Steps)
    @assert(sf == 12'u64)
}

// cast() auto-inference
#test
{
    let v: s32 = 42
    let b: bool = cast() (v > 0)
    @assert(b)
    let f: f32 = cast() v
    @assert(f > 41.0 and f < 43.0)
}

// Compound assignment operators (*=, <<=)
#test
{
    var a: u64 = 3
    a *= 7
    @assert(a == 21'u64)
    var b: u32 = 1
    b <<= 4
    @assert(b == 16'u32)
    b >>= 2
    @assert(b == 4'u32)
}

// Mixin: variance computation injects axisVariance
#test
{
    var fleet = parseFleet(SampleInput, SampleWidth, SampleHeight)
    var axisVariance: u64
    computeVarianceX(&fleet, 0)
    @assert(axisVariance > 0'u64)
}

// Clustering: bestStep should be in valid range
#test
{
    var fleet = parseFleet(SampleInput, SampleWidth, SampleHeight)
    let best = findClusterStep(&fleet, 20)
    @assert(best < 20'u32)
}

// Edge case: single robot at origin
#test
{
    var fleet: Fleet
    fleet.w = 5
    fleet.h = 5
    fleet.count = 1
    with fleet.bots[0]
    {
        .px = 0
        .py = 0
        .vx = 1
        .vy = 1
    }

    // After 3 steps: (3,3)
    let bot = advanceRobot(fleet.bots[0], 3, 5, 5)
    @assert(bot.px == 3)
    @assert(bot.py == 3)

    // After 7 steps: (7%5, 7%5) = (2,2)
    let bot2 = advanceRobot(fleet.bots[0], 7, 5, 5)
    @assert(bot2.px == 2)
    @assert(bot2.py == 2)
}

// Edge case: robot wrapping negative velocity
#test
{
    var fleet: Fleet
    fleet.w = 5
    fleet.h = 5
    fleet.count = 1
    with fleet.bots[0]
    {
        .px = 1
        .py = 1
        .vx = -3
        .vy = -3
    }

    // After 1 step: (1-3, 1-3) = (-2,-2) → (3,3)
    let bot = advanceRobot(fleet.bots[0], 1, 5, 5)
    @assert(bot.px == 3)
    @assert(bot.py == 3)
}
