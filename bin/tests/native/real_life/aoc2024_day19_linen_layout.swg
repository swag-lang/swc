#global fileprivate

// Advent of Code 2024 Day 19: match towel designs against available patterns.
// Part 1: count how many designs can be formed by concatenating patterns.
// Part 2: sum the total number of distinct ways to form each design.
// Exercises: nested #[Swag.Inline] mtd on slice-based struct, implicit
// bool cast from nested inline return, DP with fixed arrays, string slicing.

const SampleInput =
"""r, wr, b, g, bwu, rb, gb, br

brwrr
bggr
gbbr
rrbgbr
ubwu
bwurrg
brgr
bbrgwb"""

// ---------------------------------------------------------------------------
// Pattern storage
// ---------------------------------------------------------------------------

const MaxPatterns = 512'u32
const MaxPatLen   = 16'u32
const MaxDesignLen = 128'u32
const MaxDesigns  = 512'u32

struct Pattern
{
    bytes: [MaxPatLen] u8
    len:   u32
}

struct PatternList
{
    items: [MaxPatterns] Pattern
    count: u32
}

impl Pattern
{
    #[Swag.Inline]
    mtd byteAt(i: u32) -> u8 { return me.bytes[i] }

    // Nested inline: matchAt calls byteAt
    #[Swag.Inline]
    mtd matchAt(design: const [..] u8, pos: u32) -> bool
    {
        if pos + me.len > @countof(design) do
            return false
        for i in me.len
        {
            if me.byteAt(i) != design[pos + i] do
                return false
        }
        return true
    }
}

// ---------------------------------------------------------------------------
// Design storage
// ---------------------------------------------------------------------------

struct Design
{
    bytes: [MaxDesignLen] u8
    len:   u32
}

struct DesignList
{
    items: [MaxDesigns] Design
    count: u32
}

impl Design
{
    #[Swag.Inline]
    mtd asSlice() -> const [..] u8
    {
        return @mkslice(&me.bytes[0], cast(u64) me.len)
    }
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

func parseInput(text: string) -> { patterns: PatternList, designs: DesignList }
{
    var result: retval
    let bytes = cast(const [..] u8) text
    var pos: u32

    // Parse patterns (comma-separated first line)
    for
    {
        if pos >= @countof(bytes) do break

        // skip whitespace
        for
        {
            if pos >= @countof(bytes) do break
            let ch = bytes[pos]
            if ch != ' ' and ch != ',' do break
            pos += 1
        }
        if pos >= @countof(bytes) or bytes[pos] == '\n' do break

        // read pattern
        var pat: Pattern
        for
        {
            if pos >= @countof(bytes) do break
            let ch = bytes[pos]
            if ch == ',' or ch == '\n' or ch == ' ' do break
            if pat.len < MaxPatLen
            {
                pat.bytes[pat.len] = ch
                pat.len += 1
            }
            pos += 1
        }

        if pat.len > 0 and result.patterns.count < MaxPatterns
        {
            result.patterns.items[result.patterns.count] = pat
            result.patterns.count += 1
        }
    }

    // Skip past blank line(s)
    for
    {
        if pos >= @countof(bytes) do break
        let ch = bytes[pos]
        if ch != '\n' and ch != '\r' do break
        pos += 1
    }

    // Parse designs (one per line)
    for
    {
        if pos >= @countof(bytes) do break

        // skip newlines
        for
        {
            if pos >= @countof(bytes) do break
            if bytes[pos] != '\n' and bytes[pos] != '\r' do break
            pos += 1
        }
        if pos >= @countof(bytes) do break

        var des: Design
        for
        {
            if pos >= @countof(bytes) do break
            let ch = bytes[pos]
            if ch == '\n' or ch == '\r' do break
            if des.len < MaxDesignLen
            {
                des.bytes[des.len] = ch
                des.len += 1
            }
            pos += 1
        }

        if des.len > 0 and result.designs.count < MaxDesigns
        {
            result.designs.items[result.designs.count] = des
            result.designs.count += 1
        }
    }

    return result
}

// ---------------------------------------------------------------------------
// DP: count ways to form a design from patterns
// ---------------------------------------------------------------------------

func countWays(design: const [..] u8, designLen: u32, pats: *PatternList) -> u64
{
    // dp[i] = number of ways to form design[0..i]
    var dp: [MaxDesignLen + 1] u64
    dp[0] = 1

    for i in 1 until designLen + 1
    {
        for p in pats.count
        {
            let pat = &pats.items[p]
            if pat.len > i do continue
            let start = i - pat.len
            if pat.matchAt(design, start)
            {
                dp[i] += dp[start]
            }
        }
    }

    return dp[designLen]
}

// ---------------------------------------------------------------------------
// Solver
// ---------------------------------------------------------------------------

struct SolveResult
{
    possible: u32
    totalWays: u64
}

func solve(text: string) -> SolveResult
{
    var input = parseInput(text)
    var result: SolveResult

    for d in input.designs.count
    {
        let des = &input.designs.items[d]
        let sl = des.asSlice()
        let ways = countWays(sl, des.len, &input.patterns)
        if ways > 0
        {
            result.possible += 1
            result.totalWays += ways
        }
    }

    return result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// Parse patterns
#test
{
    let input = parseInput(SampleInput)
    @assert(input.patterns.count == 8'u32)
    @assert(input.patterns.items[0].len == 1'u32)
    @assert(input.patterns.items[0].bytes[0] == 'r')
    @assert(input.patterns.items[1].len == 2'u32)
    @assert(input.patterns.items[1].bytes[0] == 'w')
    @assert(input.patterns.items[1].bytes[1] == 'r')
}

// Parse designs
#test
{
    let input = parseInput(SampleInput)
    @assert(input.designs.count == 8'u32)
    @assert(input.designs.items[0].len == 5'u32)
    @assert(input.designs.items[0].bytes[0] == 'b')
}

// Pattern inline method: byteAt
#test
{
    var pat: Pattern
    pat.bytes[0] = 'a'
    pat.bytes[1] = 'b'
    pat.len = 2
    @assert(pat.byteAt(0) == 'a')
    @assert(pat.byteAt(1) == 'b')
}

// Pattern nested inline: matchAt
#test
{
    var pat: Pattern
    pat.bytes[0] = 'b'
    pat.bytes[1] = 'r'
    pat.len = 2

    var buf: [5] u8
    buf[0] = 'b'; buf[1] = 'r'; buf[2] = 'w'; buf[3] = 'r'; buf[4] = 'r'
    let sl = @mkslice(&buf[0], 5'u64)

    @assert(pat.matchAt(sl, 0))
    @assert(!pat.matchAt(sl, 1))
    @assert(!pat.matchAt(sl, 4))
}

// Design asSlice inline method — exercises inline returning a slice
#test
{
    var des: Design
    des.bytes[0] = 'x'
    des.bytes[1] = 'y'
    des.len = 2
    let sl = des.asSlice()
    @assert(@countof(sl) == 2)
    @assert(sl[0] == 'x')
    @assert(sl[1] == 'y')
}

// DP: simple single-pattern match
#test
{
    var pats: PatternList
    pats.items[0].bytes[0] = 'a'
    pats.items[0].len = 1
    pats.count = 1

    var buf: [3] u8
    buf[0] = 'a'; buf[1] = 'a'; buf[2] = 'a'
    let sl = @mkslice(&buf[0], 3'u64)
    @assert(countWays(sl, 3, &pats) == 1'u64)
}

// DP: two patterns, multiple ways
#test
{
    var pats: PatternList
    pats.items[0].bytes[0] = 'a'
    pats.items[0].len = 1
    pats.items[1].bytes[0] = 'a'
    pats.items[1].bytes[1] = 'a'
    pats.items[1].len = 2
    pats.count = 2

    var buf: [3] u8
    buf[0] = 'a'; buf[1] = 'a'; buf[2] = 'a'
    let sl = @mkslice(&buf[0], 3'u64)
    // "aaa" = a+a+a, a+aa, aa+a → 3 ways
    @assert(countWays(sl, 3, &pats) == 3'u64)
}

// DP: impossible design
#test
{
    var pats: PatternList
    pats.items[0].bytes[0] = 'a'
    pats.items[0].len = 1
    pats.count = 1

    var buf: [2] u8
    buf[0] = 'a'; buf[1] = 'b'
    let sl = @mkslice(&buf[0], 2'u64)
    @assert(countWays(sl, 2, &pats) == 0'u64)
}

// Full sample: Part 1 = 6 possible designs
#test
{
    let result = solve(SampleInput)
    @assert(result.possible == 6'u32)
}

// Full sample: Part 2 = 16 total ways
#test
{
    let result = solve(SampleInput)
    @assert(result.totalWays == 16'u64)
}

// Edge: empty design list
#test
{
    let result = solve("r, b\n\n")
    @assert(result.possible == 0'u32)
    @assert(result.totalWays == 0'u64)
}

// matchAt boundary: pattern longer than remaining design
#test
{
    var pat: Pattern
    pat.bytes[0] = 'a'
    pat.bytes[1] = 'b'
    pat.bytes[2] = 'c'
    pat.len = 3

    var buf: [2] u8
    buf[0] = 'a'; buf[1] = 'b'
    let sl = @mkslice(&buf[0], 2'u64)
    @assert(!pat.matchAt(sl, 0))
}
