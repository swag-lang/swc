#global fileprivate

// Real-life example: audit a small office LAN for trusted triplets touching a
// team-lead workstation and identify the largest fully connected admin group.

const MaxComputers = 20
const MaxPasswordBytes = MaxComputers * 3 - 1

struct LanAudit
{
    leadTripletCount: u32
    largestCliqueSize:u32
    passwordLength:   u32
    password:         [MaxPasswordBytes] u8
}

func parseLabel(bytes: const [..] u8, startIndex: u32)->u16
{
    return (cast(u16) bytes[startIndex] << 8) | cast(u16) bytes[startIndex + 1]
}

func labelFirstByte(label: u16)->u8
{
    return cast(u8) (label >> 8)
}

func labelSecondByte(label: u16)->u8
{
    return cast(u8) (label & 0x00FF'u16)
}

func labelLess(left, right: u16)->bool
{
    if labelFirstByte(left) < labelFirstByte(right) do
        return true

    if labelFirstByte(left) > labelFirstByte(right) do
        return false

    return labelSecondByte(left) < labelSecondByte(right)
}

func isLeadComputer(label: u16)->bool
{
    return labelFirstByte(label) == 't''u8
}

func edgeIndex(fromComputer, toComputer: u32)->u32
{
    return fromComputer * MaxComputers + toComputer
}

func findComputerIndex(labels: const [..] u16, labelCount: u32, target: u16)->u32
{
    for labelCount
    {
        let index = cast(u32) @index
        if labels[index] == target do
            return index
    }

    return Swag.U32.Max
}

func countBits(value: u32)->u32
{
    var bits = value
    var result: u32

    while bits != 0
    {
        if (bits & 1'u32) != 0'u32 do
            result += 1
        bits >>= 1
    }

    return result
}

func isClique(mask: u32, adjacency: const [..] bool, computerCount: u32)->bool
{
    for computerCount
    {
        let left = cast(u32) @index
        if (mask & (1'u32 << left)) == 0'u32 do
            continue

        for computerCount
        {
            let right = cast(u32) @index
            if right <= left do
                continue

            if (mask & (1'u32 << right)) == 0'u32 do
                continue

            if !adjacency[edgeIndex(left, right)] do
                return false
        }
    }

    return true
}

func buildPassword(outPassword: [..] u8, outLength: *u32, labels: const [..] u16, computerCount: u32, mask: u32)
{
    var selected: [MaxComputers] u16
    var selectedCount: u32

    for computerCount
    {
        let index = cast(u32) @index
        if (mask & (1'u32 << index)) != 0'u32
        {
            selected[selectedCount] = labels[index]
            selectedCount += 1
        }
    }

    for selectedCount
    {
        let left = cast(u32) @index
        for selectedCount
        {
            let right = cast(u32) @index
            if right <= left do
                continue

            if labelLess(selected[right], selected[left])
            {
                let temp = selected[left]
                selected[left] = selected[right]
                selected[right] = temp
            }
        }
    }

    var length: u32
    for selectedCount
    {
        let index = cast(u32) @index
        let label = selected[index]

        if index != 0
        {
            outPassword[length] = ',''u8
            length += 1
        }

        outPassword[length] = labelFirstByte(label)
        length += 1
        outPassword[length] = labelSecondByte(label)
        length += 1
    }

    dref outLength = length
}

func passwordLess(leftPassword: const [..] u8, leftLength: u32, rightPassword: const [..] u8, rightLength: u32)->bool
{
    let commonLength = @min(leftLength, rightLength)

    for commonLength
    {
        let index = cast(u32) @index
        if leftPassword[index] < rightPassword[index] do
            return true
        if leftPassword[index] > rightPassword[index] do
            return false
    }

    return leftLength < rightLength
}

func passwordMatches(audit: LanAudit, expected: string)->bool
{
    let expectedBytes = cast(const [..] u8) expected
    if audit.passwordLength != cast(u32) @countof(expectedBytes) do
        return false

    for audit.passwordLength
    {
        let index = cast(u32) @index
        if audit.password[index] != expectedBytes[index] do
            return false
    }

    return true
}

func auditLan(connections: const [..] string)->LanAudit
{
    var result: LanAudit
    var labels: [MaxComputers] u16
    var adjacency: [MaxComputers * MaxComputers] bool
    var labelSlice: [..] u16 = labels
    var adjacencySlice: [..] bool = adjacency
    var computerCount: u32

    foreach line in connections
    {
        let bytes = cast(const [..] u8) line
        @assert(@countof(bytes) == 5)
        @assert(bytes[2] == '-''u8)

        let leftLabel = parseLabel(bytes, 0)
        let rightLabel = parseLabel(bytes, 3)

        var leftIndex = findComputerIndex(labelSlice, computerCount, leftLabel)
        if leftIndex == Swag.U32.Max
        {
            @assert(computerCount < MaxComputers)
            leftIndex = computerCount
            labels[computerCount] = leftLabel
            computerCount += 1
        }

        var rightIndex = findComputerIndex(labelSlice, computerCount, rightLabel)
        if rightIndex == Swag.U32.Max
        {
            @assert(computerCount < MaxComputers)
            rightIndex = computerCount
            labels[computerCount] = rightLabel
            computerCount += 1
        }

        adjacency[edgeIndex(leftIndex, rightIndex)] = true
        adjacency[edgeIndex(rightIndex, leftIndex)] = true
    }

    for computerCount
    {
        let first = cast(u32) @index
        for computerCount
        {
            let second = cast(u32) @index
            if second <= first do
                continue

            if !adjacency[edgeIndex(first, second)] do
                continue

            for computerCount
            {
                let third = cast(u32) @index
                if third <= second do
                    continue

                if adjacency[edgeIndex(first, third)] and adjacency[edgeIndex(second, third)]
                {
                    if isLeadComputer(labels[first]) or isLeadComputer(labels[second]) or isLeadComputer(labels[third]) do
                        result.leadTripletCount += 1
                }
            }
        }
    }

    @assert(computerCount < 31)
    let subsetCount = 1'u32 << computerCount

    for subsetCount - 1
    {
        let mask = cast(u32) @index + 1
        let cliqueSize = countBits(mask)
        if cliqueSize < result.largestCliqueSize do
            continue

        if !isClique(mask, adjacencySlice, computerCount) do
            continue

        var candidatePassword: [MaxPasswordBytes] u8
        var candidatePasswordSlice: [..] u8 = candidatePassword
        var resultPasswordSlice: [..] u8 = result.password
        var candidateLength: u32
        buildPassword(candidatePasswordSlice, &candidateLength, labelSlice, computerCount, mask)

        if cliqueSize > result.largestCliqueSize or passwordLess(candidatePasswordSlice, candidateLength, resultPasswordSlice, result.passwordLength)
        {
            result.largestCliqueSize = cliqueSize
            result.passwordLength = candidateLength

            for candidateLength
            {
                let index = cast(u32) @index
                result.password[index] = candidatePassword[index]
            }
        }
    }

    return result
}

#test
{
    const sampleConnections: [32] string =
    [
        "kh-tc",
        "qp-kh",
        "de-cg",
        "ka-co",
        "yn-aq",
        "qp-ub",
        "cg-tb",
        "vc-aq",
        "tb-ka",
        "wh-tc",
        "yn-cg",
        "kh-ub",
        "ta-co",
        "de-co",
        "tc-td",
        "tb-wq",
        "wh-td",
        "ta-ka",
        "td-qp",
        "aq-cg",
        "wq-ub",
        "ub-vc",
        "de-ta",
        "wq-aq",
        "wq-vc",
        "wh-yn",
        "ka-de",
        "kh-ta",
        "co-tc",
        "wh-qp",
        "tb-vc",
        "td-yn",
    ]

    let sampleAudit = auditLan(sampleConnections)

    @assert(sampleAudit.leadTripletCount == 7)
    @assert(sampleAudit.largestCliqueSize == 4)
    @assert(passwordMatches(sampleAudit, "co,de,ka,ta"))

    const compactConnections: [6] string =
    [
        "aa-bb",
        "aa-cc",
        "aa-tt",
        "bb-cc",
        "bb-tt",
        "cc-tt",
    ]

    let compactAudit = auditLan(compactConnections)

    @assert(compactAudit.leadTripletCount == 3)
    @assert(compactAudit.largestCliqueSize == 4)
    @assert(passwordMatches(compactAudit, "aa,bb,cc,tt"))
}
