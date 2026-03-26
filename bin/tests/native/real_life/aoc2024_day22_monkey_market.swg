#global fileprivate

// Advent of Code 2024 Day 22: pseudorandom secret number evolution.
// Part 1: sum of 2000th secret numbers.
// Part 2: find the 4-change price sequence that maximises bananas.
// Exercises: bitwise XOR, #run compile-time tables, for #reverse sliding
// window, with &ptr blocks, inline + retval, @mkslice in inline, large
// heap arrays. Note: nested inline calls with variable args are avoided
// (known compiler limitation with double inline expansion).

const SamplePart1 =
"""1
10
100
2024"""

const SamplePart2 =
"""1
2
3
2024"""

// ---------------------------------------------------------------------------
// Secret evolution (bitwise operations)
// ---------------------------------------------------------------------------

const Prune: u64 = 16777216  // 2^24

#[Swag.Inline]
func mix(secret: u64, val: u64) -> u64 { return secret ^ val }

#[Swag.Inline]
func prune(secret: u64) -> u64 { return secret % Prune }

func evolve(secret: u64) -> u64
{
    var s = secret
    var v = s * 64
    var m = mix(s, v)
    s = prune(m)
    v = s / 32
    m = mix(s, v)
    s = prune(m)
    v = s * 2048
    m = mix(s, v)
    s = prune(m)
    return s
}

func evolveN(secret: u64, n: u32) -> u64
{
    var s = secret
    for n { s = evolve(s) }
    return s
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

const MaxBuyers = 2500'u32

struct BuyerList
{
    secrets: [MaxBuyers] u64
    count:   u32
}

func parseBuyers(text: string) -> BuyerList
{
    var result: BuyerList
    let bytes = cast(const [..] u8) text
    var pos: u32
    var inNum = false
    var acc: u64

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
            if result.count < MaxBuyers
            {
                result.secrets[result.count] = acc
                result.count += 1
            }
            acc = 0
            inNum = false
        }
    }

    if inNum and result.count < MaxBuyers
    {
        result.secrets[result.count] = acc
        result.count += 1
    }

    return result
}

// ---------------------------------------------------------------------------
// Part 1: sum of Nth secret
// ---------------------------------------------------------------------------

func solvePart1(buyers: *BuyerList, steps: u32) -> u64
{
    var total: u64
    for i in buyers.count
    {
        total += evolveN(buyers.secrets[i], steps)
    }
    return total
}

// ---------------------------------------------------------------------------
// Part 2: best 4-change sequence
// ---------------------------------------------------------------------------

// Encode a sequence of 4 changes (each in -9..9) as a single index.
// Shift each change by +9 to make it 0..18, then pack as base-19 digits.
const SeqBase  = 19'u32
const SeqCount = SeqBase * SeqBase * SeqBase * SeqBase  // 130321

#[Swag.Inline]
func encodeSeq(d0: s32, d1: s32, d2: s32, d3: s32) -> u32
{
    let a = cast(u32) (d0 + 9)
    let b = cast(u32) (d1 + 9)
    let c = cast(u32) (d2 + 9)
    let d = cast(u32) (d3 + 9)
    return ((a * SeqBase + b) * SeqBase + c) * SeqBase + d
}

// Inline returning struct via retval (exercises the retval fix)
struct SeqResult
{
    bestBananas: u64
}

#[Swag.Inline]
func makeSeqResult(val: u64) -> SeqResult
{
    var r: retval
    r.bestBananas = val
    return r
}

func solvePart2(buyers: *BuyerList, steps: u32) -> SeqResult
{
    // Global totals for each possible 4-change sequence
    let totals = cast([*] u64) @alloc(cast(u64) SeqCount * #sizeof(u64))
    defer @free(totals)
    for SeqCount { totals[@index] = 0 }

    // Per-buyer seen flags
    let seen = cast([*] bool) @alloc(cast(u64) SeqCount * #sizeof(bool))
    defer @free(seen)

    for bi in buyers.count
    {
        // Clear seen flags
        for SeqCount { seen[@index] = false }

        var s = buyers.secrets[bi]
        var prevPrice = cast(s32) (s % 10)

        // Collect changes
        var ch: [4] s32
        for step in steps
        {
            s = evolve(s)
            let price = cast(s32) (s % 10)
            let change = price - prevPrice
            prevPrice = price

            // Slide the window using for #reverse, then insert new change
            for #reverse i in 1 until 4
            {
                ch[i] = ch[i - 1]
            }
            ch[0] = change

            // Need 4 changes before first check
            if step >= 3
            {
                // Encode oldest→newest: ch[3], ch[2], ch[1], ch[0]
                let idx = encodeSeq(ch[3], ch[2], ch[1], ch[0])
                if !seen[idx]
                {
                    seen[idx] = true
                    totals[idx] += cast(u64) price
                }
            }
        }
    }

    // Find maximum
    var best: u64
    for SeqCount
    {
        if totals[@index] > best do
            best = totals[@index]
    }

    return makeSeqResult(best)
}

// ---------------------------------------------------------------------------
// Solver
// ---------------------------------------------------------------------------

struct SolveResult
{
    part1: u64
    part2: u64
}

func solve(text: string) -> SolveResult
{
    var buyers = parseBuyers(text)
    var result: SolveResult
    result.part1 = solvePart1(&buyers, 2000)
    let p2 = solvePart2(&buyers, 2000)
    result.part2 = p2.bestBananas
    return result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// Evolution basics
#test
{
    var s: u64 = 123
    s = evolve(s)
    @assert(s == 15887950'u64)
    s = evolve(s)
    @assert(s == 16495136'u64)
}

// evolveN
#test
{
    @assert(evolveN(1, 2000) == 8685429'u64)
    @assert(evolveN(10, 2000) == 4700978'u64)
    @assert(evolveN(100, 2000) == 15273692'u64)
    @assert(evolveN(2024, 2000) == 8667524'u64)
}

// Parsing
#test
{
    let buyers = parseBuyers(SamplePart1)
    @assert(buyers.count == 4'u32)
    @assert(buyers.secrets[0] == 1'u64)
    @assert(buyers.secrets[1] == 10'u64)
    @assert(buyers.secrets[2] == 100'u64)
    @assert(buyers.secrets[3] == 2024'u64)
}

// Part 1
#test
{
    var buyers = parseBuyers(SamplePart1)
    @assert(solvePart1(&buyers, 2000) == 37327623'u64)
}

// encodeSeq inline
#test
{
    let idx = encodeSeq(-2, 1, -1, 3)
    @assert(idx < SeqCount)
    // Different sequences give different indices
    let idx2 = encodeSeq(0, 0, 0, 0)
    @assert(idx != idx2)
}

// makeSeqResult inline + retval
#test
{
    let r = makeSeqResult(42)
    @assert(r.bestBananas == 42'u64)
}

// for #reverse sliding window
#test
{
    var ch: [4] s32
    ch[0] = 10; ch[1] = 20; ch[2] = 30; ch[3] = 40
    for #reverse i in 1 until 4 { ch[i] = ch[i - 1] }
    ch[0] = 99
    @assert(ch[0] == 99)
    @assert(ch[1] == 10)
    @assert(ch[2] == 20)
    @assert(ch[3] == 30)
}

// Part 2 sample: best sequence gives 23 bananas
#test
{
    var buyers = parseBuyers(SamplePart2)
    let p2 = solvePart2(&buyers, 2000)
    @assert(p2.bestBananas == 23'u64)
}

// mix and prune inline
#test
{
    @assert(mix(42, 15) == 37'u64)     // 42 ^ 15 = 37
    @assert(prune(100000000) == 16113920'u64)  // 100000000 % 16777216
}

// with &ptr on Coord (exercises the with-pointer fix)
#test
{
    var sr: SolveResult
    with &sr
    {
        .part1 = 111
        .part2 = 222
    }
    @assert(sr.part1 == 111'u64)
    @assert(sr.part2 == 222'u64)
}

// @mkslice in inline (exercises the mkslice fix)
struct SliceBuf
{
    data: [8] u8
    len:  u32
}

impl SliceBuf
{
    #[Swag.Inline]
    mtd asSlice() -> const [..] u8
    {
        return @mkslice(&me.data[0], cast(u64) me.len)
    }
}

#test
{
    var buf: SliceBuf
    buf.data[0] = 'H'
    buf.data[1] = 'i'
    buf.len = 2
    let sl = buf.asSlice()
    @assert(@countof(sl) == 2)
    @assert(sl[0] == 'H')
    @assert(sl[1] == 'i')
}
