#global fileprivate

// Real-life example: evaluate a small crossed-signal control board and flag
// outputs that clearly violate the expected ripple-carry wiring rules.

const MaxWires = 96
const MaxGates = 64
const MaxSuspects = 32

enum GateOp: u8
{
    And
    Or
    Xor
}

struct WireValue
{
    name:  string
    value: u8
}

struct LogicGate
{
    left:   string
    op:     GateOp
    right:  string
    output: string
}

struct BoardAudit
{
    outputValue:  u64
    suspectCount: u32
    suspects:     [MaxSuspects] string
}

func stringLess(left, right: string)->bool
{
    let leftBytes = cast(const [..] u8) left
    let rightBytes = cast(const [..] u8) right
    let commonLength = @min(@countof(leftBytes), @countof(rightBytes))

    for commonLength
    {
        let index = cast(u32) @index
        if leftBytes[index] < rightBytes[index] do
            return true
        if leftBytes[index] > rightBytes[index] do
            return false
    }

    return @countof(leftBytes) < @countof(rightBytes)
}

func parseWireIndex(name: string)->u32
{
    let bytes = cast(const [..] u8) name
    @assert(@countof(bytes) == 3)
    @assert(bytes[1] >= '0' and bytes[1] <= '9')
    @assert(bytes[2] >= '0' and bytes[2] <= '9')
    return cast(u32) (bytes[1] - '0') * 10'u32 + cast(u32) (bytes[2] - '0')
}

func startsWith(name: string, prefix: u8)->bool
{
    let bytes = cast(const [..] u8) name
    return @countof(bytes) == 3 and bytes[0] == prefix
}

func isInputWire(name: string)->bool
{
    return startsWith(name, 'x''u8) or startsWith(name, 'y''u8)
}

func isOutputWire(name: string)->bool
{
    return startsWith(name, 'z''u8)
}

func isLeastSignificantInputPair(left, right: string)->bool
{
    return (left == "x00" and right == "y00") or (left == "y00" and right == "x00")
}

func evaluateGate(leftValue, rightValue: u8, op: GateOp)->u8
{
    if op == GateOp.And do
        return leftValue & rightValue
    if op == GateOp.Or do
        return leftValue | rightValue
    return leftValue ^ rightValue
}

func findWireIndex(wireNames: const [..] string, wireCount: u32, name: string)->u32
{
    for wireCount
    {
        let index = cast(u32) @index
        if wireNames[index] == name do
            return index
    }

    return Swag.U32.Max
}

func registerSuspect(suspects: [..] string, suspectCount: *u32, name: string)
{
    for dref suspectCount
    {
        let index = cast(u32) @index
        if suspects[index] == name do
            return
    }

    @assert(dref suspectCount < MaxSuspects)
    suspects[dref suspectCount] = name
    dref suspectCount += 1
}

func hasConsumerOp(gates: const [..] LogicGate, wireName: string, op: GateOp)->bool
{
    foreach gate in gates
    {
        if gate.op == op and (gate.left == wireName or gate.right == wireName) do
            return true
    }

    return false
}

func highestOutputBit(gates: const [..] LogicGate)->u32
{
    var result: u32

    foreach gate in gates
    {
        if isOutputWire(gate.output)
        {
            let index = parseWireIndex(gate.output)
            if index > result do
                result = index
        }
    }

    return result
}

func sortSuspects(suspects: [..] string, suspectCount: u32)
{
    for suspectCount
    {
        let left = cast(u32) @index
        for suspectCount
        {
            let right = cast(u32) @index
            if right <= left do
                continue

            if stringLess(suspects[right], suspects[left])
            {
                let temp = suspects[left]
                suspects[left] = suspects[right]
                suspects[right] = temp
            }
        }
    }
}

func suspectsMatch(audit: BoardAudit, expected: const [..] string)->bool
{
    if audit.suspectCount != cast(u32) @countof(expected) do
        return false

    for audit.suspectCount
    {
        let index = cast(u32) @index
        if audit.suspects[index] != expected[index] do
            return false
    }

    return true
}

func auditBoard(initialWires: const [..] WireValue, gates: const [..] LogicGate)->BoardAudit
{
    var result: BoardAudit
    var wireNames: [MaxWires] string
    var wireKnown: [MaxWires] bool
    var wireValues: [MaxWires] u8
    var wireNameSlice: [..] string = wireNames
    var suspectSlice: [..] string = result.suspects
    var wireCount: u32

    foreach wire in initialWires
    {
        @assert(wireCount < MaxWires)
        wireNames[wireCount] = wire.name
        wireKnown[wireCount] = true
        wireValues[wireCount] = wire.value
        wireCount += 1
    }

    @assert(@countof(gates) <= MaxGates)
    var gateResolved: [MaxGates] bool
    var resolvedCount: u32

    while resolvedCount < cast(u32) @countof(gates)
    {
        var progress = false

        foreach gate, gateIndex in gates
        {
            if gateResolved[gateIndex] do
                continue

            let leftIndex = findWireIndex(wireNameSlice, wireCount, gate.left)
            let rightIndex = findWireIndex(wireNameSlice, wireCount, gate.right)
            if leftIndex == Swag.U32.Max or rightIndex == Swag.U32.Max do
                continue
            if !wireKnown[leftIndex] or !wireKnown[rightIndex] do
                continue

            var outputIndex = findWireIndex(wireNameSlice, wireCount, gate.output)
            if outputIndex == Swag.U32.Max
            {
                @assert(wireCount < MaxWires)
                outputIndex = wireCount
                wireNames[wireCount] = gate.output
                wireCount += 1
            }

            wireValues[outputIndex] = evaluateGate(wireValues[leftIndex], wireValues[rightIndex], gate.op)
            wireKnown[outputIndex] = true
            gateResolved[gateIndex] = true
            resolvedCount += 1
            progress = true
        }

        @assert(progress)
    }

    for wireCount
    {
        let wireIndex = cast(u32) @index
        if wireKnown[wireIndex] and isOutputWire(wireNames[wireIndex]) and wireValues[wireIndex] != 0
        {
            let bitIndex = parseWireIndex(wireNames[wireIndex])
            result.outputValue |= 1'u64 << bitIndex
        }
    }

    let highestZ = highestOutputBit(gates)
    foreach gate in gates
    {
        if isOutputWire(gate.output) and parseWireIndex(gate.output) != highestZ and gate.op != GateOp.Xor do
            registerSuspect(suspectSlice, &result.suspectCount, gate.output)

        if !isOutputWire(gate.output) and gate.op == GateOp.Xor and !isInputWire(gate.left) and !isInputWire(gate.right) do
            registerSuspect(suspectSlice, &result.suspectCount, gate.output)

        if gate.op == GateOp.And and !isLeastSignificantInputPair(gate.left, gate.right) and !hasConsumerOp(gates, gate.output, GateOp.Or) do
            registerSuspect(suspectSlice, &result.suspectCount, gate.output)

        if gate.op == GateOp.Xor and isInputWire(gate.left) and isInputWire(gate.right) and !isLeastSignificantInputPair(gate.left, gate.right) and !hasConsumerOp(gates, gate.output, GateOp.Xor) do
            registerSuspect(suspectSlice, &result.suspectCount, gate.output)
    }

    sortSuspects(suspectSlice, result.suspectCount)
    return result
}

#test
{
    const sampleInputs: [10] WireValue =
    [
        {name: "x00", value: 1},
        {name: "x01", value: 0},
        {name: "x02", value: 1},
        {name: "x03", value: 1},
        {name: "x04", value: 0},
        {name: "y00", value: 1},
        {name: "y01", value: 1},
        {name: "y02", value: 1},
        {name: "y03", value: 1},
        {name: "y04", value: 1},
    ]

    const sampleGates: [36] LogicGate =
    [
        {left: "ntg", op: GateOp.Xor, right: "fgs", output: "mjb"},
        {left: "y02", op: GateOp.Or, right: "x01", output: "tnw"},
        {left: "kwq", op: GateOp.Or, right: "kpj", output: "z05"},
        {left: "x00", op: GateOp.Or, right: "x03", output: "fst"},
        {left: "tgd", op: GateOp.Xor, right: "rvg", output: "z01"},
        {left: "vdt", op: GateOp.Or, right: "tnw", output: "bfw"},
        {left: "bfw", op: GateOp.And, right: "frj", output: "z10"},
        {left: "ffh", op: GateOp.Or, right: "nrd", output: "bqk"},
        {left: "y00", op: GateOp.And, right: "y03", output: "djm"},
        {left: "y03", op: GateOp.Or, right: "y00", output: "psh"},
        {left: "bqk", op: GateOp.Or, right: "frj", output: "z08"},
        {left: "tnw", op: GateOp.Or, right: "fst", output: "frj"},
        {left: "gnj", op: GateOp.And, right: "tgd", output: "z11"},
        {left: "bfw", op: GateOp.Xor, right: "mjb", output: "z00"},
        {left: "x03", op: GateOp.Or, right: "x00", output: "vdt"},
        {left: "gnj", op: GateOp.And, right: "wpb", output: "z02"},
        {left: "x04", op: GateOp.And, right: "y00", output: "kjc"},
        {left: "djm", op: GateOp.Or, right: "pbm", output: "qhw"},
        {left: "nrd", op: GateOp.And, right: "vdt", output: "hwm"},
        {left: "kjc", op: GateOp.And, right: "fst", output: "rvg"},
        {left: "y04", op: GateOp.Or, right: "y02", output: "fgs"},
        {left: "y01", op: GateOp.And, right: "x02", output: "pbm"},
        {left: "ntg", op: GateOp.Or, right: "kjc", output: "kwq"},
        {left: "psh", op: GateOp.Xor, right: "fgs", output: "tgd"},
        {left: "qhw", op: GateOp.Xor, right: "tgd", output: "z09"},
        {left: "pbm", op: GateOp.Or, right: "djm", output: "kpj"},
        {left: "x03", op: GateOp.Xor, right: "y03", output: "ffh"},
        {left: "x00", op: GateOp.Xor, right: "y04", output: "ntg"},
        {left: "bfw", op: GateOp.Or, right: "bqk", output: "z06"},
        {left: "nrd", op: GateOp.Xor, right: "fgs", output: "wpb"},
        {left: "frj", op: GateOp.Xor, right: "qhw", output: "z04"},
        {left: "bqk", op: GateOp.Or, right: "frj", output: "z07"},
        {left: "y03", op: GateOp.Or, right: "x01", output: "nrd"},
        {left: "hwm", op: GateOp.And, right: "bqk", output: "z03"},
        {left: "tgd", op: GateOp.Xor, right: "rvg", output: "z12"},
        {left: "tnw", op: GateOp.Or, right: "pbm", output: "gnj"},
    ]

    let sampleAudit = auditBoard(sampleInputs, sampleGates)

    @assert(sampleAudit.outputValue == 2024'u64)

    const swappedInputs: [6] WireValue =
    [
        {name: "x00", value: 1},
        {name: "x01", value: 0},
        {name: "x02", value: 1},
        {name: "y00", value: 1},
        {name: "y01", value: 1},
        {name: "y02", value: 0},
    ]

    const swappedAdder: [12] LogicGate =
    [
        {left: "x00", op: GateOp.Xor, right: "y00", output: "z00"},
        {left: "x00", op: GateOp.And, right: "y00", output: "c01"},
        {left: "x01", op: GateOp.Xor, right: "y01", output: "s01"},
        {left: "x01", op: GateOp.And, right: "y01", output: "z01"},
        {left: "s01", op: GateOp.Xor, right: "c01", output: "a01"},
        {left: "s01", op: GateOp.And, right: "c01", output: "t01"},
        {left: "t01", op: GateOp.Or, right: "z01", output: "c02"},
        {left: "x02", op: GateOp.Xor, right: "y02", output: "s02"},
        {left: "x02", op: GateOp.And, right: "y02", output: "a02"},
        {left: "s02", op: GateOp.Xor, right: "c02", output: "z02"},
        {left: "s02", op: GateOp.And, right: "c02", output: "t02"},
        {left: "t02", op: GateOp.Or, right: "a02", output: "z03"},
    ]

    let swappedAudit = auditBoard(swappedInputs, swappedAdder)
    const expectedSuspects: [2] string = ["a01", "z01"]

    @assert(swappedAudit.outputValue == 8'u64)
    @assert(suspectsMatch(swappedAudit, expectedSuspects))
}
