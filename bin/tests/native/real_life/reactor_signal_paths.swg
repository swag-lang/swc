#global fileprivate

// Real-life example: count how many valid control-signal routes can move through
// a reactor rack and measure how deep the longest route becomes.

enum ReactorNode : s32
{
    Intake,
    Mixer,
    Heater,
    Cooler,
    Valve,
    Sensor,
    Relay,
    Buffer,
    Chamber,
    Output,
}

const NodeCount = 10
const MaxOutputsPerNode = 3

struct ReactorGraph
{
    outputCounts: [NodeCount] u32
    outputs:      [NodeCount, MaxOutputsPerNode] u32
}

struct ReactorReport
{
    pathCount:          u32
    busiestBranchPaths: u32
    longestChain:       u32
}

func resetMemo(memo: [..] s32)
{
    for @countof(memo)
    {
        memo[@index] = -1
    }
}

func countPaths(memo: [..] s32, graph: ReactorGraph, nodeIndex: u32)->u32
{
    if nodeIndex == cast(u32) ReactorNode.Output do
        return 1

    let cached = memo[nodeIndex]
    if cached >= 0 do
        return cast(u32) cached

    var total: u32
    let outputCount = graph.outputCounts[nodeIndex]

    for outputCount
    {
        let nextIndex = graph.outputs[nodeIndex][@index]
        total += countPaths(memo, graph, nextIndex)
    }

    memo[nodeIndex] = cast(s32) total
    return total
}

func longestChain(memo: [..] s32, graph: ReactorGraph, nodeIndex: u32)->u32
{
    if nodeIndex == cast(u32) ReactorNode.Output do
        return 0

    let cached = memo[nodeIndex]
    if cached >= 0 do
        return cast(u32) cached

    var best: u32
    let outputCount = graph.outputCounts[nodeIndex]

    for outputCount
    {
        let nextIndex = graph.outputs[nodeIndex][@index]
        let candidate = 1'u32 + longestChain(memo, graph, nextIndex)
        if candidate > best do
            best = candidate
    }

    memo[nodeIndex] = cast(s32) best
    return best
}

func auditReactor(graph: ReactorGraph)->ReactorReport
{
    var pathMemoStorage: [NodeCount] s32
    var chainMemoStorage: [NodeCount] s32
    var pathMemo: [..] s32 = pathMemoStorage
    var chainMemo: [..] s32 = chainMemoStorage

    resetMemo(pathMemo)
    resetMemo(chainMemo)

    var result: ReactorReport
    result.pathCount = countPaths(pathMemo, graph, cast(u32) ReactorNode.Intake)
    result.longestChain = longestChain(chainMemo, graph, cast(u32) ReactorNode.Intake)

    let intakeIndex = cast(u32) ReactorNode.Intake
    let branchCount = graph.outputCounts[intakeIndex]

    for branchCount
    {
        var branchMemoStorage: [NodeCount] s32
        var branchMemo: [..] s32 = branchMemoStorage
        resetMemo(branchMemo)

        let nextIndex = graph.outputs[intakeIndex][@index]
        let branchPaths = countPaths(branchMemo, graph, nextIndex)
        if branchPaths > result.busiestBranchPaths do
            result.busiestBranchPaths = branchPaths
    }

    return result
}

func buildSampleReactor()->ReactorGraph
{
    const Intake = cast(u32) ReactorNode.Intake
    const Mixer = cast(u32) ReactorNode.Mixer
    const Heater = cast(u32) ReactorNode.Heater
    const Cooler = cast(u32) ReactorNode.Cooler
    const Valve = cast(u32) ReactorNode.Valve
    const Sensor = cast(u32) ReactorNode.Sensor
    const Relay = cast(u32) ReactorNode.Relay
    const Buffer = cast(u32) ReactorNode.Buffer
    const Chamber = cast(u32) ReactorNode.Chamber
    const Output = cast(u32) ReactorNode.Output

    var result: ReactorGraph

    result.outputCounts[Intake] = 3
    result.outputs[Intake][0] = Mixer
    result.outputs[Intake][1] = Heater
    result.outputs[Intake][2] = Sensor

    result.outputCounts[Mixer] = 2
    result.outputs[Mixer][0] = Valve
    result.outputs[Mixer][1] = Buffer

    result.outputCounts[Heater] = 2
    result.outputs[Heater][0] = Valve
    result.outputs[Heater][1] = Cooler

    result.outputCounts[Cooler] = 1
    result.outputs[Cooler][0] = Chamber

    result.outputCounts[Valve] = 2
    result.outputs[Valve][0] = Chamber
    result.outputs[Valve][1] = Relay

    result.outputCounts[Sensor] = 1
    result.outputs[Sensor][0] = Relay

    result.outputCounts[Relay] = 2
    result.outputs[Relay][0] = Chamber
    result.outputs[Relay][1] = Output

    result.outputCounts[Buffer] = 1
    result.outputs[Buffer][0] = Chamber

    result.outputCounts[Chamber] = 1
    result.outputs[Chamber][0] = Output

    return result
}

func buildCompactReactor()->ReactorGraph
{
    const Intake = cast(u32) ReactorNode.Intake
    const Mixer = cast(u32) ReactorNode.Mixer
    const Heater = cast(u32) ReactorNode.Heater
    const Valve = cast(u32) ReactorNode.Valve
    const Chamber = cast(u32) ReactorNode.Chamber
    const Output = cast(u32) ReactorNode.Output

    var result: ReactorGraph

    result.outputCounts[Intake] = 2
    result.outputs[Intake][0] = Mixer
    result.outputs[Intake][1] = Heater

    result.outputCounts[Mixer] = 2
    result.outputs[Mixer][0] = Valve
    result.outputs[Mixer][1] = Chamber

    result.outputCounts[Heater] = 2
    result.outputs[Heater][0] = Chamber
    result.outputs[Heater][1] = Output

    result.outputCounts[Valve] = 1
    result.outputs[Valve][0] = Output

    result.outputCounts[Chamber] = 1
    result.outputs[Chamber][0] = Output

    return result
}

#test
{
    let sampleReport = auditReactor(buildSampleReactor())

    @assert(sampleReport.pathCount == 10'u32)
    @assert(sampleReport.busiestBranchPaths == 4'u32)
    @assert(sampleReport.longestChain == 5'u32)

    let compactReport = auditReactor(buildCompactReactor())

    @assert(compactReport.pathCount == 4'u32)
    @assert(compactReport.busiestBranchPaths == 2'u32)
    @assert(compactReport.longestChain == 3'u32)
}
