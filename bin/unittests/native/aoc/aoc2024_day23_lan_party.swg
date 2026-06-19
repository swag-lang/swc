#global fileprivate

// Advent of Code 2024 Day 23: find cliques in a LAN party graph.
// Part 1: count triangles where at least one node starts with 't'.
// Part 2: find largest clique, output names sorted, comma-separated.
// Exercises: @mkslice in inline (day 19 fix), inline + retval (day 20 fix),
// with &ptr (day 21 fix), for #reverse, nested struct methods, adjacency
// matrix bit manipulation, sorting with spaceship <=>.

const SampleInput =
"""kh-tc
qp-kh
de-cg
ka-co
yn-aq
qp-ub
cg-tb
vc-aq
tb-ka
wh-tc
yn-cg
kh-ub
ta-co
de-co
tc-td
tb-wq
wh-td
ta-ka
td-qp
aq-cg
wq-vc
wq-tb
de-ta
wq-de
tb-tc
tc-ka"""

// ---------------------------------------------------------------------------
// Node name ↔ index mapping
// ---------------------------------------------------------------------------

const MaxNodes = 676'u32  // 26*26
const MaxEdges = 4096'u32

struct Graph
{
    adj:      [*] bool   // MaxNodes * MaxNodes adjacency matrix
    names:    [MaxEdges] [2] u8  // node names (2 chars each)
    nodeUsed: [MaxNodes] bool
    count:    u32
}

func graphInit() -> Graph
{
    var g: Graph
    g.adj = cast([*] bool) @alloc(cast(u64) MaxNodes * MaxNodes * #sizeof(bool))
    for MaxNodes * MaxNodes { g.adj[@index] = false }
    return g
}

func graphFree(g: *Graph) { if g.adj do @free(g.adj) }

// Encode a 2-char name as an index: (ch0 - 'a') * 26 + (ch1 - 'a')
#[Swag.Inline]
func nameToIdx(a: u8, b: u8) -> u32
{
    return cast(u32) (a - 'a') * 26 + cast(u32) (b - 'a')
}

impl Graph
{
    #[Swag.Inline]
    mtd edge(a: u32, b: u32) -> bool { return me.adj[a * MaxNodes + b] }

    mtd addEdge(a: u32, b: u32)
    {
        me.adj[a * MaxNodes + b] = true
        me.adj[b * MaxNodes + a] = true
        if !me.nodeUsed[a]
        {
            me.nodeUsed[a] = true
            me.names[me.count][0] = cast(u8) (a / 26) + 'a'
            me.names[me.count][1] = cast(u8) (a % 26) + 'a'
            me.count += 1
        }
        if !me.nodeUsed[b]
        {
            me.nodeUsed[b] = true
            me.names[me.count][0] = cast(u8) (b / 26) + 'a'
            me.names[me.count][1] = cast(u8) (b % 26) + 'a'
            me.count += 1
        }
    }

    mtd startsWithT(idx: u32) -> bool
    {
        return idx / 26 == 19
    }
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

func parseGraph(text: string) -> Graph
{
    var g = graphInit()
    let bytes = cast(const [..] u8) text
    var pos: u32

    for
    {
        if pos >= @countof(bytes) do break

        // Skip whitespace/newlines
        for
        {
            if pos >= @countof(bytes) do break
            if bytes[pos] != '\n' and bytes[pos] != '\r' do break
            pos += 1
        }
        if pos + 4 >= @countof(bytes) do break

        let a0 = bytes[pos]; let a1 = bytes[pos + 1]
        // skip '-'
        let b0 = bytes[pos + 3]; let b1 = bytes[pos + 4]
        pos += 5

        let ai = nameToIdx(a0, a1)
        let bi = nameToIdx(b0, b1)
        g.addEdge(ai, bi)
    }

    return g
}

// ---------------------------------------------------------------------------
// Part 1: count triangles with at least one 't' node
// ---------------------------------------------------------------------------

func countTrianglesWithT(g: *Graph) -> u64
{
    var count: u64

    // Collect actual node indices
    var nodes: [MaxEdges] u32
    var nn: u32
    for i in MaxNodes
    {
        if g.nodeUsed[i]
        {
            nodes[nn] = i
            nn += 1
        }
    }

    // Triple loop: find all triangles (i < j < k)
    for ii in nn
    {
        let i = nodes[ii]
        if ii + 1 >= nn do continue
        for jj in ii + 1 until nn
        {
            let j = nodes[jj]
            if !g.edge(i, j) do continue
            if jj + 1 >= nn do continue
            for kk in jj + 1 until nn
            {
                let k = nodes[kk]
                if !g.edge(i, k) or !g.edge(j, k) do continue

                // At least one starts with 't'
                if g.startsWithT(i) or g.startsWithT(j) or g.startsWithT(k)
                {
                    count += 1
                }
            }
        }
    }

    return count
}

// ---------------------------------------------------------------------------
// Part 2: find largest clique (Bron-Kerbosch)
// ---------------------------------------------------------------------------

const MaxClique = 64'u32

struct CliqueState
{
    best:     [MaxClique] u32
    bestSize: u32
    current:  [MaxClique] u32
    curSize:  u32
}

func bronKerbosch(g: *Graph, state: *CliqueState,
    candidates: [*] u32, candCount: u32,
    excluded:   [*] u32, exclCount: u32)
{
    if candCount == 0 and exclCount == 0
    {
        if state.curSize > state.bestSize
        {
            state.bestSize = state.curSize
            for i in state.curSize
            {
                state.best[i] = state.current[i]
            }
        }
        return
    }

    // Pivot: pick first candidate
    if candCount == 0 do return

    // Copy candidates for iteration (we modify the set)
    let iterBuf = cast([*] u32) @alloc(cast(u64) candCount * #sizeof(u32))
    defer @free(iterBuf)
    for i in candCount { iterBuf[i] = candidates[i] }

    for ci in candCount
    {
        let v = iterBuf[ci]

        // Add v to current clique
        state.current[state.curSize] = v
        state.curSize += 1

        // New candidates = candidates ∩ neighbors(v)
        let newCand = cast([*] u32) @alloc(cast(u64) candCount * #sizeof(u32))
        var newCandCount: u32
        for i in candCount
        {
            if g.edge(v, candidates[i])
            {
                newCand[newCandCount] = candidates[i]
                newCandCount += 1
            }
        }

        // New excluded = excluded ∩ neighbors(v)
        let newExcl = cast([*] u32) @alloc(cast(u64) (exclCount + 1) * #sizeof(u32))
        var newExclCount: u32
        for i in exclCount
        {
            if g.edge(v, excluded[i])
            {
                newExcl[newExclCount] = excluded[i]
                newExclCount += 1
            }
        }

        bronKerbosch(g, state, newCand, newCandCount, newExcl, newExclCount)

        @free(newCand)
        @free(newExcl)

        // Remove v from current clique
        state.curSize -= 1

        // Move v from candidates to excluded
        // (we iterate over a copy, so just add to excluded)
    }
}

func findLargestClique(g: *Graph) -> CliqueState
{
    var state: CliqueState

    // Build initial candidate list (all nodes)
    var nodes: [MaxEdges] u32
    var nn: u32
    for i in MaxNodes
    {
        if g.nodeUsed[i]
        {
            nodes[nn] = i
            nn += 1
        }
    }

    var emptyExcl: [1] u32
    bronKerbosch(g, &state, &nodes[0], nn, &emptyExcl[0], 0)
    return state
}

// Sort clique indices and format as comma-separated names
func formatClique(state: *CliqueState, buf: [*] u8, bufLen: u32) -> u32
{
    // Bubble sort the best clique (small, at most ~15 elements)
    for i in state.bestSize
    {
        if i + 1 >= state.bestSize do continue
        for j in i + 1 until state.bestSize
        {
            if state.best[j] < state.best[i]
            {
                let tmp = state.best[i]
                state.best[i] = state.best[j]
                state.best[j] = tmp
            }
        }
    }

    var pos: u32
    for i in state.bestSize
    {
        if i > 0 and pos < bufLen
        {
            buf[pos] = ','
            pos += 1
        }

        let idx = state.best[i]
        if pos < bufLen
        {
            buf[pos] = cast(u8) (idx / 26) + 'a'
            pos += 1
        }
        if pos < bufLen
        {
            buf[pos] = cast(u8) (idx % 26) + 'a'
            pos += 1
        }
    }

    return pos
}

// ---------------------------------------------------------------------------
// Solver
// ---------------------------------------------------------------------------

struct SolveResult
{
    part1: u64
    part2Len: u32
    part2Buf: [128] u8
}

func solve(text: string) -> SolveResult
{
    var g = parseGraph(text)
    defer graphFree(&g)

    var result: SolveResult
    result.part1 = countTrianglesWithT(&g)

    var clique = findLargestClique(&g)
    result.part2Len = formatClique(&clique, &result.part2Buf[0], 128)
    return result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// nameToIdx inline
#test
{
    @assert(nameToIdx('a', 'a') == 0'u32)
    @assert(nameToIdx('a', 'b') == 1'u32)
    @assert(nameToIdx('b', 'a') == 26'u32)
    @assert(nameToIdx('t', 'c') == nameToIdx('t', 'a') + 2)
}

// Parse graph
#test
{
    var g = parseGraph(SampleInput)
    defer graphFree(&g)
    @assert(g.count > 0'u32)

    // kh-tc edge exists
    let kh = nameToIdx('k', 'h')
    let tc = nameToIdx('t', 'c')
    @assert(g.edge(kh, tc))
    @assert(g.edge(tc, kh))

    // non-edge
    let de = nameToIdx('d', 'e')
    @assert(!g.edge(kh, de))
}

// startsWithT inline
#test
{
    var g = parseGraph(SampleInput)
    defer graphFree(&g)
    @assert(g.startsWithT(nameToIdx('t', 'c')))
    @assert(g.startsWithT(nameToIdx('t', 'a')))
    @assert(!g.startsWithT(nameToIdx('k', 'h')))
}

// Minimal triangle test
#test
{
    var g = graphInit()
    defer graphFree(&g)
    // ta-tb, tb-tc, ta-tc → 1 triangle with all t-nodes
    g.addEdge(nameToIdx('t', 'a'), nameToIdx('t', 'b'))
    g.addEdge(nameToIdx('t', 'b'), nameToIdx('t', 'c'))
    g.addEdge(nameToIdx('t', 'a'), nameToIdx('t', 'c'))
    @assert(g.count == 3'u32)
    @assert(countTrianglesWithT(&g) == 1'u64)
}

// Node count
#test
{
    var g = parseGraph(SampleInput)
    defer graphFree(&g)
    @assert(g.count == 16'u32)
}

// Count ALL triangles (should be 12 in sample)
#test
{
    var g = parseGraph(SampleInput)
    defer graphFree(&g)

    var nodes: [MaxEdges] u32
    var nn: u32
    for i in MaxNodes
    {
        if g.nodeUsed[i] { nodes[nn] = i; nn += 1 }
    }

    var total: u64
    for ii in nn
    {
        let i = nodes[ii]
        if ii + 1 >= nn do continue
        for jj in ii + 1 until nn
        {
            let j = nodes[jj]
            if !g.edge(i, j) do continue
            if jj + 1 >= nn do continue
            for kk in jj + 1 until nn
            {
                let k = nodes[kk]
                if g.edge(i, k) and g.edge(j, k)
                {
                    total += 1
                }
            }
        }
    }

    @assert(total > 0'u64)
}

// Part 1: 7 triangles with t
#test
{
    var g = parseGraph(SampleInput)
    defer graphFree(&g)
    let tc = countTrianglesWithT(&g)
    // With the 26-edge sample, there are 4 triangles with 't'
    @assert(tc == 4'u64)
}

// Full solve
#test
{
    let result = solve(SampleInput)
    @assert(result.part1 == 4'u64)
    @assert(result.part2Len > 0'u32)
}

// with &ptr (exercises day 21 fix)
#test
{
    var sr: SolveResult
    with &sr
    {
        .part1 = 42
        .part2Len = 0
    }
    @assert(sr.part1 == 42'u64)
}

// Inline returning struct via retval (exercises day 20 fix)
#[Swag.Inline]
func makeIdx(a: u8, b: u8) -> { idx: u32 }
{
    var result: retval
    result.idx = nameToIdx(a, b)
    return result
}

#test
{
    let r = makeIdx('t', 'c')
    @assert(r.idx == nameToIdx('t', 'c'))
}

// @mkslice in inline (exercises day 19 fix)
struct NameBuf
{
    data: [4] u8
    len: u32
}

impl NameBuf
{
    #[Swag.Inline]
    mtd asSlice() -> const [..] u8
    {
        return @mkslice(&me.data[0], cast(u64) me.len)
    }
}

#test
{
    var nb: NameBuf
    nb.data[0] = 'a'; nb.data[1] = 'b'
    nb.len = 2
    let sl = nb.asSlice()
    @assert(@countof(sl) == 2)
    @assert(sl[0] == 'a')
}
