#global fileprivate

// Advent of Code 2024 Day 24: Crossed Wires
// Part 1: simulate logic gates (AND, OR, XOR), read z-wires as a binary number.
// Part 2: detect 4 swapped output pairs in a ripple-carry adder.
// Exercises: enum, switch on enum, inline methods, nested inline calls,
// bitwise shifts for binary construction, with &ptr blocks, dynamic memory,
// sorting, struct returns via retval, boolean chains, cast patterns,
// ternary expressions, for loops with until.

const SampleSmall =
"""x00: 1
x01: 1
x02: 1
y00: 0
y01: 1
y02: 0"""

const SampleSmallGates =
"""x00 AND y00 -> z00
x01 XOR y01 -> z01
x02 OR y02 -> z02"""

const SampleLarge =
"""x00: 1
x01: 0
x02: 1
x03: 1
x04: 0
y00: 1
y01: 1
y02: 1
y03: 1
y04: 1"""

const SampleLargeGates =
"""ntg XOR fgs -> mjb
y02 OR x01 -> tnw
kwq OR kpj -> z05
x00 OR x03 -> fst
tgd XOR rvg -> z01
vdt OR tnw -> bfw
bfw AND frj -> z10
ffh OR nrd -> bqk
y00 AND y03 -> djm
y03 OR y00 -> psh
bqk OR frj -> z08
tnw OR fst -> frj
gnj AND tgd -> z11
bfw XOR mjb -> z00
x03 OR x00 -> vdt
gnj AND wpb -> z02
x04 AND y00 -> kjc
djm OR pbm -> qhw
nrd AND vdt -> hwm
kjc AND fst -> rvg
y04 OR y02 -> fgs
y01 AND x02 -> pbm
ntg OR kjc -> kwq
psh XOR fgs -> tgd
qhw XOR tgd -> z09
pbm OR djm -> kpj
x03 XOR y03 -> ffh
x00 XOR y04 -> ntg
bfw OR bqk -> gnj
wpb XOR gnj -> z03
x04 OR y01 -> wpb
z07 XOR gnj -> z04
y02 AND x02 -> z07
ntg AND fgs -> nrd
wpb AND kdm -> z06
y03 AND x05 -> kdm"""

// ---------------------------------------------------------------------------
// Gate operation enum
// ---------------------------------------------------------------------------

enum GateOp: u8
{
    OpAnd
    OpOr
    OpXor
}

// ---------------------------------------------------------------------------
// Wire name encoding (3 chars -> u32 index)
// ---------------------------------------------------------------------------

const MaxWireIdx = 46656'u32  // 36^3: max possible encodeWire result + 1

// Each wire name is 3 characters. Encode as: (c0 * 36 + c1) * 36 + c2
// where digits 0-9 map to 0-9 and letters a-z map to 10-35.
#[Swag.Inline]
func charVal(c: u8) -> u32
{
    if c >= '0' and c <= '9' do return cast(u32) (c - '0')
    return cast(u32) (c - 'a') + 10
}

#[Swag.Inline]
func encodeWire(c0: u8, c1: u8, c2: u8) -> u32
{
    return (charVal(c0) * 36 + charVal(c1)) * 36 + charVal(c2)
}

#[Swag.Inline]
func wireIsZ(c0: u8) -> bool { return c0 == 'z' }

#[Swag.Inline]
func wireIsX(c0: u8) -> bool { return c0 == 'x' }

#[Swag.Inline]
func wireIsY(c0: u8) -> bool { return c0 == 'y' }

// ---------------------------------------------------------------------------
// Gate and circuit structures
// ---------------------------------------------------------------------------

struct Gate
{
    inA:    u32      // encoded wire name
    inB:    u32
    out:    u32
    op:     GateOp
    nameA0: u8       // first char of wire A name (for x/y/z checks)
    nameB0: u8
    nameOut0: u8
    nameOut1: u8
    nameOut2: u8
}

const MaxGates = 256'u32

struct Circuit
{
    // Wire values: index by encoded name
    wireVal:  [*] u8     // 0 or 1 or 255 (unset)
    gates:    [MaxGates] Gate
    gateCount: u32

    // For output: track which z-wires exist
    maxZBit:  u32        // highest z-bit number
}

func circuitInit() -> Circuit
{
    var c: Circuit
    c.wireVal = cast([*] u8) @alloc(cast(u64) MaxWireIdx * #sizeof(u8))
    let total = MaxWireIdx
    for total { c.wireVal[@index] = 255 }
    c.maxZBit = 0
    return c
}

func circuitFree(c: *Circuit)
{
    if c.wireVal do @free(c.wireVal)
}

impl Circuit
{
    #[Swag.Inline]
    mtd getWire(idx: u32) -> u8
    {
        return me.wireVal[idx]
    }

    #[Swag.Inline]
    mtd setWire(idx: u32, val: u8)
    {
        me.wireVal[idx] = val
    }

    #[Swag.Inline]
    mtd isSet(idx: u32) -> bool
    {
        return me.wireVal[idx] != 255
    }
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

#[Swag.Inline]
func skipWhitespace(bytes: const [..] u8, pos: *u32)
{
    for
    {
        if dref pos >= @countof(bytes) do break
        let ch = bytes[dref pos]
        if ch != ' ' and ch != '\r' and ch != '\n' and ch != '\t' do break
        dref pos += 1
    }
}

#[Swag.Inline]
func skipToNewline(bytes: const [..] u8, pos: *u32)
{
    for
    {
        if dref pos >= @countof(bytes) do break
        if bytes[dref pos] == '\n' do break
        if bytes[dref pos] == '\r' do break
        dref pos += 1
    }
}

func parseInitialWires(c: *Circuit, text: string)
{
    let bytes = cast(const [..] u8) text
    var pos: u32

    for
    {
        skipWhitespace(bytes, &pos)
        if pos >= @countof(bytes) do break

        // Format: "x00: 1"
        if pos + 5 >= @countof(bytes) do break

        let c0 = bytes[pos]
        let c1 = bytes[pos + 1]
        let c2 = bytes[pos + 2]
        // pos+3 is ':'
        // pos+4 is ' '
        let val = bytes[pos + 5] - '0'
        pos += 6

        let idx = encodeWire(c0, c1, c2)
        c.setWire(idx, val)

        skipToNewline(bytes, &pos)
    }
}

func parseGates(c: *Circuit, text: string)
{
    let bytes = cast(const [..] u8) text
    var pos: u32

    for
    {
        skipWhitespace(bytes, &pos)
        if pos >= @countof(bytes) do break

        // Format: "aaa OP bbb -> ccc"
        // Read first wire name (3 chars)
        if pos + 2 >= @countof(bytes) do break
        let a0 = bytes[pos]; let a1 = bytes[pos + 1]; let a2 = bytes[pos + 2]
        pos += 4  // skip name + space

        // Read operator
        var op: GateOp
        if pos + 2 < @countof(bytes) and bytes[pos] == 'A' and bytes[pos + 1] == 'N' and bytes[pos + 2] == 'D'
        {
            op = GateOp.OpAnd
            pos += 4
        }
        elif pos + 1 < @countof(bytes) and bytes[pos] == 'O' and bytes[pos + 1] == 'R'
        {
            op = GateOp.OpOr
            // Check if next char is space (OR) vs other
            pos += 3
        }
        elif pos + 2 < @countof(bytes) and bytes[pos] == 'X' and bytes[pos + 1] == 'O' and bytes[pos + 2] == 'R'
        {
            op = GateOp.OpXor
            pos += 4
        }
        else
        {
            break
        }

        // Read second wire name
        if pos + 2 >= @countof(bytes) do break
        let b0 = bytes[pos]; let b1 = bytes[pos + 1]; let b2 = bytes[pos + 2]
        pos += 4  // skip name + space

        // Skip "->"
        if pos + 2 < @countof(bytes) and bytes[pos] == '-' and bytes[pos + 1] == '>'
        {
            pos += 3
        }
        else
        {
            break
        }

        // Read output wire name
        if pos + 2 >= @countof(bytes) do break
        let o0 = bytes[pos]; let o1 = bytes[pos + 1]; let o2 = bytes[pos + 2]
        pos += 3

        let gi = c.gateCount
        c.gates[gi].inA = encodeWire(a0, a1, a2)
        c.gates[gi].inB = encodeWire(b0, b1, b2)
        c.gates[gi].out = encodeWire(o0, o1, o2)
        c.gates[gi].op = op
        c.gates[gi].nameA0 = a0
        c.gates[gi].nameB0 = b0
        c.gates[gi].nameOut0 = o0
        c.gates[gi].nameOut1 = o1
        c.gates[gi].nameOut2 = o2
        c.gateCount += 1

        // Track max z-bit
        if o0 == 'z'
        {
            let bitNum = cast(u32) (o1 - '0') * 10 + cast(u32) (o2 - '0')
            if bitNum > c.maxZBit do c.maxZBit = bitNum
        }

        skipToNewline(bytes, &pos)
    }
}

// ---------------------------------------------------------------------------
// Part 1: simulate gates
// ---------------------------------------------------------------------------

// Note: cannot use switch here due to compiler bug #5918:
// inline switch + return crashes when switch expression is a var.
#[Swag.Inline]
func evalGate(op: GateOp, a: u8, b: u8) -> u8
{
    if op == GateOp.OpAnd do return a & b
    if op == GateOp.OpOr  do return a | b
    if op == GateOp.OpXor do return a ^ b
    return 0
}

func simulate(c: *Circuit)
{
    // Keep iterating until all gates resolved
    var changed = true
    for
    {
        if !changed do break
        changed = false
        for gi in c.gateCount
        {
            let g = &c.gates[gi]
            if c.isSet(g.out) do continue
            if !c.isSet(g.inA) or !c.isSet(g.inB) do continue

            let va = c.getWire(g.inA)
            let vb = c.getWire(g.inB)
            let result = evalGate(g.op, va, vb)
            c.setWire(g.out, result)
            changed = true
        }
    }
}

func readZValue(c: *Circuit) -> u64
{
    var result: u64
    for bit in c.maxZBit + 1
    {
        let d0 = cast(u8) (bit / 10) + '0'
        let d1 = cast(u8) (bit % 10) + '0'
        let idx = encodeWire('z', d0, d1)
        if c.isSet(idx)
        {
            let val = c.getWire(idx)
            if val == 1
            {
                result = result | (1'u64 << cast(u64) bit)
            }
        }
    }
    return result
}

func solvePart1(wiresText: string, gatesText: string) -> u64
{
    var c = circuitInit()
    defer circuitFree(&c)

    parseInitialWires(&c, wiresText)
    parseGates(&c, gatesText)
    simulate(&c)
    return readZValue(&c)
}

// ---------------------------------------------------------------------------
// Part 2: detect swapped gate outputs in a ripple-carry adder
// ---------------------------------------------------------------------------

// Rules for a correct ripple-carry adder:
// 1. If output is z-wire, gate must be XOR (except highest z-bit which is carry out)
// 2. If output is NOT z-wire and inputs are NOT x/y, gate must NOT be XOR
// 3. XOR gate with x/y inputs must have its output used by another XOR gate
// 4. AND gate (not x00 AND y00) must have its output used by an OR gate

struct SwappedResult
{
    names: [8] [3] u8    // up to 8 swapped wire names
    count: u32
}

#[Swag.Inline]
func isXY(ch: u8) -> bool
{
    return ch == 'x' or ch == 'y'
}

func addSwapped(result: *SwappedResult, c0: u8, c1: u8, c2: u8)
{
    // Check for duplicates
    for i in result.count
    {
        if result.names[i][0] == c0 and result.names[i][1] == c1 and result.names[i][2] == c2
        {
            return
        }
    }
    if result.count < 8
    {
        result.names[result.count][0] = c0
        result.names[result.count][1] = c1
        result.names[result.count][2] = c2
        result.count += 1
    }
}

// Check if any gate uses `wireOut` as an input with the given operation
func hasDownstream(c: *Circuit, wireOut: u32, op: GateOp) -> bool
{
    for gi in c.gateCount
    {
        let g = &c.gates[gi]
        if g.op == op and (g.inA == wireOut or g.inB == wireOut)
        {
            return true
        }
    }
    return false
}

func findSwapped(c: *Circuit) -> SwappedResult
{
    var result: SwappedResult

    for gi in c.gateCount
    {
        let g = &c.gates[gi]

        let outIsZ = g.nameOut0 == 'z'
        let inputsAreXY = isXY(g.nameA0) and isXY(g.nameB0)

        // Highest z-bit is the carry-out, skip it for rule 1
        let isHighestZ = outIsZ and g.nameOut1 == cast(u8) (c.maxZBit / 10) + '0' and g.nameOut2 == cast(u8) (c.maxZBit % 10) + '0'

        // Rule 1: z-output gates must be XOR (except highest)
        if outIsZ and !isHighestZ and g.op != GateOp.OpXor
        {
            addSwapped(&result, g.nameOut0, g.nameOut1, g.nameOut2)
        }

        // Rule 2: non-z output with non-xy inputs must NOT be XOR
        if !outIsZ and !inputsAreXY and g.op == GateOp.OpXor
        {
            addSwapped(&result, g.nameOut0, g.nameOut1, g.nameOut2)
        }

        // Rule 3: XOR with x/y inputs -> output must feed another XOR
        // (except x00 XOR y00 which directly produces z00)
        if g.op == GateOp.OpXor and inputsAreXY
        {
            let isFirstBit = (g.nameA0 == 'x' and g.nameA0 + 0 == 'x' and
                encodeWire(g.nameA0, cast(u8) '0', cast(u8) '0') == g.inA) or
                (g.nameB0 == 'x' and
                encodeWire(g.nameB0, cast(u8) '0', cast(u8) '0') == g.inB)

            if !isFirstBit and !hasDownstream(c, g.out, GateOp.OpXor)
            {
                addSwapped(&result, g.nameOut0, g.nameOut1, g.nameOut2)
            }
        }

        // Rule 4: AND (not first bit) -> output must feed an OR
        if g.op == GateOp.OpAnd and inputsAreXY
        {
            let isFirstBit = (g.nameA0 == 'x' and
                encodeWire(g.nameA0, cast(u8) '0', cast(u8) '0') == g.inA) or
                (g.nameB0 == 'x' and
                encodeWire(g.nameB0, cast(u8) '0', cast(u8) '0') == g.inB)

            if !isFirstBit and !hasDownstream(c, g.out, GateOp.OpOr)
            {
                addSwapped(&result, g.nameOut0, g.nameOut1, g.nameOut2)
            }
        }
    }

    return result
}

// Sort swapped names and format as comma-separated
func formatSwapped(result: *SwappedResult, buf: [*] u8, bufLen: u32) -> u32
{
    // Bubble sort by name
    for i in result.count
    {
        if i + 1 >= result.count do continue
        for j in i + 1 until result.count
        {
            var swap = false
            if result.names[j][0] < result.names[i][0] do swap = true
            elif result.names[j][0] == result.names[i][0]
            {
                if result.names[j][1] < result.names[i][1] do swap = true
                elif result.names[j][1] == result.names[i][1] and result.names[j][2] < result.names[i][2]
                {
                    swap = true
                }
            }

            if swap
            {
                // Swap entries
                for k in 3'u32
                {
                    let tmp = result.names[i][k]
                    result.names[i][k] = result.names[j][k]
                    result.names[j][k] = tmp
                }
            }
        }
    }

    var pos: u32
    for i in result.count
    {
        if i > 0 and pos < bufLen
        {
            buf[pos] = ','
            pos += 1
        }
        for k in 3'u32
        {
            if pos < bufLen
            {
                buf[pos] = result.names[i][k]
                pos += 1
            }
        }
    }

    return pos
}

// ---------------------------------------------------------------------------
// Full solver
// ---------------------------------------------------------------------------

struct SolveResult
{
    part1:    u64
    part2Len: u32
    part2Buf: [128] u8
}

func solve(wiresText: string, gatesText: string) -> SolveResult
{
    var c = circuitInit()
    defer circuitFree(&c)

    parseInitialWires(&c, wiresText)
    parseGates(&c, gatesText)

    var result: SolveResult

    // Part 1
    simulate(&c)
    result.part1 = readZValue(&c)

    // Part 2
    var swapped = findSwapped(&c)
    result.part2Len = formatSwapped(&swapped, &result.part2Buf[0], 128)

    return result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// charVal inline
#test
{
    @assert(charVal('0') == 0'u32)
    @assert(charVal('9') == 9'u32)
    @assert(charVal('a') == 10'u32)
    @assert(charVal('z') == 35'u32)
}

// encodeWire inline
#test
{
    let z00 = encodeWire('z', '0', '0')
    let z01 = encodeWire('z', '0', '1')
    @assert(z00 != z01)
    @assert(z01 == z00 + 1)

    let x00 = encodeWire('x', '0', '0')
    let y00 = encodeWire('y', '0', '0')
    @assert(x00 != y00)
}

// Wire checks inline
#test
{
    @assert(wireIsZ('z'))
    @assert(!wireIsZ('x'))
    @assert(wireIsX('x'))
    @assert(wireIsY('y'))
    @assert(!wireIsY('z'))
}

// GateOp enum
#test
{
    var op = GateOp.OpAnd
    @assert(op == GateOp.OpAnd)
    op = GateOp.OpOr
    @assert(op != GateOp.OpAnd)
    op = GateOp.OpXor
    @assert(op == GateOp.OpXor)
}

// evalGate inline with switch on enum
#test
{
    @assert(evalGate(GateOp.OpAnd, 1, 1) == 1)
    @assert(evalGate(GateOp.OpAnd, 1, 0) == 0)
    @assert(evalGate(GateOp.OpAnd, 0, 1) == 0)
    @assert(evalGate(GateOp.OpOr,  1, 0) == 1)
    @assert(evalGate(GateOp.OpOr,  0, 0) == 0)
    @assert(evalGate(GateOp.OpXor, 1, 1) == 0)
    @assert(evalGate(GateOp.OpXor, 1, 0) == 1)
}

// Parse initial wires
#test
{
    var c = circuitInit()
    defer circuitFree(&c)

    parseInitialWires(&c, SampleSmall)

    let x00 = encodeWire('x', '0', '0')
    let x01 = encodeWire('x', '0', '1')
    let x02 = encodeWire('x', '0', '2')
    let y00 = encodeWire('y', '0', '0')
    let y01 = encodeWire('y', '0', '1')
    let y02 = encodeWire('y', '0', '2')

    @assert(c.isSet(x00))
    @assert(c.getWire(x00) == 1)
    @assert(c.getWire(x01) == 1)
    @assert(c.getWire(x02) == 1)
    @assert(c.getWire(y00) == 0)
    @assert(c.getWire(y01) == 1)
    @assert(c.getWire(y02) == 0)
}

// Parse gates
#test
{
    var c = circuitInit()
    defer circuitFree(&c)

    parseGates(&c, SampleSmallGates)

    @assert(c.gateCount == 3'u32)
    @assert(c.gates[0].op == GateOp.OpAnd)
    @assert(c.gates[1].op == GateOp.OpXor)
    @assert(c.gates[2].op == GateOp.OpOr)
    @assert(c.gates[0].nameOut0 == 'z')
}

// Small example: part 1
#test
{
    let result = solvePart1(SampleSmall, SampleSmallGates)
    // z00 = x00 AND y00 = 1&0 = 0
    // z01 = x01 XOR y01 = 1^1 = 0
    // z02 = x02 OR y02 = 1|0 = 1
    // binary: z02 z01 z00 = 100 = 4
    @assert(result == 4'u64)
}

// Large example: gate parsing check
#test
{
    var c = circuitInit()
    defer circuitFree(&c)
    parseGates(&c, SampleLargeGates)
    // SampleLargeGates has 36 gates
    @assert(c.gateCount == 36'u32)
    @assert(c.maxZBit == 11'u32)
}

// Large example: part 1
// Manually traced: z00=0,z01=0,z02=1,z03=0,z04=0,z05=1,z06=0,z07=1,z08=1,z09=1,z10=1,z11=0
// = 4+32+128+256+512+1024 = 1956
#test
{
    var c = circuitInit()
    defer circuitFree(&c)
    parseInitialWires(&c, SampleLarge)
    parseGates(&c, SampleLargeGates)
    simulate(&c)

    @assert(c.getWire(encodeWire('z', '0', '0')) == 0)
    @assert(c.getWire(encodeWire('z', '0', '1')) == 0)
    @assert(c.getWire(encodeWire('z', '0', '2')) == 1)

    let val = readZValue(&c)
    @assert(val == 1956'u64)
}

// with &ptr block (exercises with-pointer codegen)
#test
{
    var sr: SolveResult
    with &sr
    {
        .part1 = 99
        .part2Len = 3
    }
    @assert(sr.part1 == 99'u64)
    @assert(sr.part2Len == 3'u32)
}

// Circuit init/free (exercises dynamic memory)
#test
{
    var c = circuitInit()
    @assert(!c.isSet(0))
    c.setWire(0, 1)
    @assert(c.isSet(0))
    @assert(c.getWire(0) == 1)
    circuitFree(&c)
}

// isXY inline
#test
{
    @assert(isXY('x'))
    @assert(isXY('y'))
    @assert(!isXY('z'))
    @assert(!isXY('a'))
}

// addSwapped dedup (exercises struct with array of arrays)
#test
{
    var result: SwappedResult
    addSwapped(&result, 'z', '0', '1')
    addSwapped(&result, 'z', '0', '1')  // duplicate
    addSwapped(&result, 'z', '0', '2')
    @assert(result.count == 2'u32)
}

// formatSwapped sorting (exercises sorting + output formatting)
#test
{
    var result: SwappedResult
    addSwapped(&result, 'z', '0', '5')
    addSwapped(&result, 'a', 'b', 'c')
    addSwapped(&result, 'z', '0', '1')

    var buf: [64] u8
    let len = formatSwapped(&result, &buf[0], 64)
    // Should be sorted: abc,z01,z05
    @assert(len == 11'u32)
    @assert(buf[0] == 'a')
    @assert(buf[1] == 'b')
    @assert(buf[2] == 'c')
    @assert(buf[3] == ',')
    @assert(buf[4] == 'z')
    @assert(buf[5] == '0')
    @assert(buf[6] == '1')
    @assert(buf[7] == ',')
    @assert(buf[8] == 'z')
    @assert(buf[9] == '0')
    @assert(buf[10] == '5')
}

// Bit shifting for z-value construction (exercises u64 shifts)
#test
{
    var c = circuitInit()
    defer circuitFree(&c)
    c.maxZBit = 3

    // Set z00=1, z01=0, z02=1, z03=1 -> binary 1101 = 13
    c.setWire(encodeWire('z', '0', '0'), 1)
    c.setWire(encodeWire('z', '0', '1'), 0)
    c.setWire(encodeWire('z', '0', '2'), 1)
    c.setWire(encodeWire('z', '0', '3'), 1)

    let val = readZValue(&c)
    @assert(val == 13'u64)
}

// Inline returning struct via retval (exercises retval pattern)
struct WireInfo
{
    encoded: u32
    isOutput: bool
}

#[Swag.Inline]
func makeWireInfo(c0: u8, c1: u8, c2: u8) -> WireInfo
{
    var r: retval
    r.encoded = encodeWire(c0, c1, c2)
    r.isOutput = wireIsZ(c0)
    return r
}

#test
{
    let wi = makeWireInfo('z', '0', '1')
    @assert(wi.isOutput)
    @assert(wi.encoded == encodeWire('z', '0', '1'))

    let wi2 = makeWireInfo('x', '0', '0')
    @assert(!wi2.isOutput)
}

// Nested inline calls: makeWireInfo calls encodeWire and wireIsZ (both inline)
#test
{
    let a = makeWireInfo('a', 'b', 'c')
    let b = makeWireInfo('a', 'b', 'c')
    @assert(a.encoded == b.encoded)
}

// hasDownstream (exercises loop + enum comparison)
#test
{
    var c = circuitInit()
    defer circuitFree(&c)

    // Add a gate: abc XOR def -> ghi
    c.gates[0].inA = encodeWire('a', 'b', 'c')
    c.gates[0].inB = encodeWire('d', 'e', 'f')
    c.gates[0].out = encodeWire('g', 'h', 'i')
    c.gates[0].op = GateOp.OpXor
    c.gateCount = 1

    @assert(hasDownstream(&c, encodeWire('a', 'b', 'c'), GateOp.OpXor))
    @assert(!hasDownstream(&c, encodeWire('a', 'b', 'c'), GateOp.OpAnd))
    @assert(!hasDownstream(&c, encodeWire('z', 'z', 'z'), GateOp.OpXor))
}

// Full solve with small example
#test
{
    let result = solve(SampleSmall, SampleSmallGates)
    @assert(result.part1 == 4'u64)
}

// Full solve with large example
#test
{
    let result = solve(SampleLarge, SampleLargeGates)
    @assert(result.part1 == 1956'u64)
}

// Enum value equality after assignment (exercises enum codegen)
#test
{
    var ops: [3] GateOp
    ops[0] = GateOp.OpAnd
    ops[1] = GateOp.OpOr
    ops[2] = GateOp.OpXor

    for i in 3'u32
    {
        var expected: GateOp
        if i == 0 do expected = GateOp.OpAnd
        elif i == 1 do expected = GateOp.OpOr
        else do expected = GateOp.OpXor
        @assert(ops[i] == expected)
    }
}

// Switch on enum in evalGate (exercises switch codegen for inline)
#test
{
    // Test all combinations
    var ops: [3] GateOp
    ops[0] = GateOp.OpAnd
    ops[1] = GateOp.OpOr
    ops[2] = GateOp.OpXor

    var inputs: [4] [2] u8
    inputs[0][0] = 0; inputs[0][1] = 0
    inputs[1][0] = 0; inputs[1][1] = 1
    inputs[2][0] = 1; inputs[2][1] = 0
    inputs[3][0] = 1; inputs[3][1] = 1

    var expected: [3] [4] u8
    // AND: 0,0,0,1
    expected[0][0] = 0; expected[0][1] = 0; expected[0][2] = 0; expected[0][3] = 1
    // OR: 0,1,1,1
    expected[1][0] = 0; expected[1][1] = 1; expected[1][2] = 1; expected[1][3] = 1
    // XOR: 0,1,1,0
    expected[2][0] = 0; expected[2][1] = 1; expected[2][2] = 1; expected[2][3] = 0

    for oi in 3'u32
    {
        for ii in 4'u32
        {
            let result = evalGate(ops[oi], inputs[ii][0], inputs[ii][1])
            @assert(result == expected[oi][ii])
        }
    }
}

// Simulate: single gate chain (exercises iterative gate resolution)
#test
{
    var c = circuitInit()
    defer circuitFree(&c)

    // a=1, b=1; a AND b -> mid; mid XOR a -> out
    let wa = encodeWire('a', 'a', 'a')
    let wb = encodeWire('b', 'b', 'b')
    let wm = encodeWire('m', 'i', 'd')
    let wo = encodeWire('z', '0', '0')

    c.setWire(wa, 1)
    c.setWire(wb, 1)

    c.gates[0].inA = wa
    c.gates[0].inB = wb
    c.gates[0].out = wm
    c.gates[0].op = GateOp.OpAnd
    c.gates[0].nameOut0 = 'm'

    c.gates[1].inA = wm
    c.gates[1].inB = wa
    c.gates[1].out = wo
    c.gates[1].op = GateOp.OpXor
    c.gates[1].nameOut0 = 'z'
    c.gates[1].nameOut1 = '0'
    c.gates[1].nameOut2 = '0'

    c.gateCount = 2
    c.maxZBit = 0

    simulate(&c)
    let val = readZValue(&c)
    // a AND b = 1, then 1 XOR 1 = 0, so z00 = 0
    @assert(val == 0'u64)
}
