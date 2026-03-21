#global fileprivate

// Real-life example: plan the shortest multi-stage keypad entry sequence for a
// set of secured door panel codes.

const MaxKeypadDepth = 26

var DirectionalMemo: [MaxKeypadDepth + 1][5][5] u64

struct KeyPos
{
    x: s32
    y: s32
}

struct PathBuffer
{
    buttons: [8] u8
    count:   u32
}

func isNumericKey(x, y: s32)->bool
{
    return y >= 0 and y < 4 and x >= 0 and x < 3 and !(x == 0 and y == 3)
}

func isDirectionalKey(x, y: s32)->bool
{
    return y >= 0 and y < 2 and x >= 0 and x < 3 and !(x == 0 and y == 0)
}

func numericPos(key: u8)->KeyPos
{
    switch key
    {
        case '7''u8: return {0, 0}
        case '8''u8: return {1, 0}
        case '9''u8: return {2, 0}
        case '4''u8: return {0, 1}
        case '5''u8: return {1, 1}
        case '6''u8: return {2, 1}
        case '1''u8: return {0, 2}
        case '2''u8: return {1, 2}
        case '3''u8: return {2, 2}
        case '0''u8: return {1, 3}
        case 'A''u8: return {2, 3}
        default:
            @assert(false)
            return {0, 0}
    }
}

func directionalPos(key: u8)->KeyPos
{
    switch key
    {
        case '^''u8: return {1, 0}
        case 'A''u8: return {2, 0}
        case '<''u8: return {0, 1}
        case 'v''u8: return {1, 1}
        case '>''u8: return {2, 1}
        default:
            @assert(false)
            return {0, 0}
    }
}

func directionalKeyIndex(key: u8)->u32
{
    switch key
    {
        case '^''u8: return 0
        case 'A''u8: return 1
        case '<''u8: return 2
        case 'v''u8: return 3
        case '>''u8: return 4
        default:
            @assert(false)
            return 0
    }
}

func absValue(value: s32)->u32
{
    if value < 0 do
        return cast(u32) (-value)
    return cast(u32) value
}

func buildPath(outPath: *PathBuffer, fromPos, toPos: KeyPos, directionalPad: bool, horizontalFirst: bool)->bool
{
    var path: PathBuffer
    var x = fromPos.x
    var y = fromPos.y
    let dx = toPos.x - fromPos.x
    let dy = toPos.y - fromPos.y

    var horizontalMove = '>''u8
    if dx < 0 do
        horizontalMove = '<''u8

    var verticalMove = 'v''u8
    if dy < 0 do
        verticalMove = '^''u8
    let horizontalCount = absValue(dx)
    let verticalCount = absValue(dy)

    var firstMove = horizontalMove
    var firstCount = horizontalCount
    var secondMove = verticalMove
    var secondCount = verticalCount

    if !horizontalFirst
    {
        firstMove = verticalMove
        firstCount = verticalCount
        secondMove = horizontalMove
        secondCount = horizontalCount
    }

    for firstCount
    {
        switch firstMove
        {
            case '<''u8: x -= 1
            case '>''u8: x += 1
            case '^''u8: y -= 1
            case 'v''u8: y += 1
            default: @assert(false)
        }

        if directionalPad
        {
            if !isDirectionalKey(x, y) do
                return false
        }
        else
        {
            if !isNumericKey(x, y) do
                return false
        }

        path.buttons[path.count] = firstMove
        path.count += 1
    }

    for secondCount
    {
        switch secondMove
        {
            case '<''u8: x -= 1
            case '>''u8: x += 1
            case '^''u8: y -= 1
            case 'v''u8: y += 1
            default: @assert(false)
        }

        if directionalPad
        {
            if !isDirectionalKey(x, y) do
                return false
        }
        else
        {
            if !isNumericKey(x, y) do
                return false
        }

        path.buttons[path.count] = secondMove
        path.count += 1
    }

    path.buttons[path.count] = 'A''u8
    path.count += 1
    dref outPath = path
    return true
}

func sequenceCost(path: PathBuffer, depth: u32)->u64
{
    if depth == 0 do
        return cast(u64) path.count

    var total: u64
    var current = 'A''u8

    for path.count
    {
        let next = path.buttons[@index]
        let fromIndex = directionalKeyIndex(current)
        let toIndex = directionalKeyIndex(next)
        let cached = DirectionalMemo[depth][fromIndex][toIndex]

        if cached != 0
        {
            total += cached
        }
        else
        {
            let fromPos = directionalPos(current)
            let toPos = directionalPos(next)
            var candidateA: PathBuffer
            var candidateB: PathBuffer
            var best = Swag.U64.Max

            if buildPath(&candidateA, fromPos, toPos, true, true)
            {
                let value = sequenceCost(candidateA, depth - 1)
                if value < best do
                    best = value
            }

            if buildPath(&candidateB, fromPos, toPos, true, false)
            {
                let value = sequenceCost(candidateB, depth - 1)
                if value < best do
                    best = value
            }

            DirectionalMemo[depth][fromIndex][toIndex] = best
            total += best
        }

        current = next
    }

    return total
}

func codeValue(code: string)->u64
{
    let bytes = cast(const [..] u8) code
    var value: u64

    foreach ch in bytes
    {
        if ch == 'A''u8 do
            break
        value = value * 10'u64 + cast(u64) (ch - '0''u8)
    }

    return value
}

func codePressCount(code: string, depth: u32)->u64
{
    let bytes = cast(const [..] u8) code
    var total: u64
    var current = 'A''u8

    foreach next in bytes
    {
        let fromPos = numericPos(current)
        let toPos = numericPos(next)
        var candidateA: PathBuffer
        var candidateB: PathBuffer
        var best = Swag.U64.Max

        if buildPath(&candidateA, fromPos, toPos, false, true)
        {
            let value = sequenceCost(candidateA, depth)
            if value < best do
                best = value
        }

        if buildPath(&candidateB, fromPos, toPos, false, false)
        {
            let value = sequenceCost(candidateB, depth)
            if value < best do
                best = value
        }

        total += best
        current = next
    }

    return total
}

func complexitySum(codes: const [..] string, depth: u32)->u64
{
    var total: u64

    foreach code in codes
    {
        total += codeValue(code) * codePressCount(code, depth)
    }

    return total
}

#test
{
    const sampleCodes: [5] string =
    [
        "029A",
        "980A",
        "179A",
        "456A",
        "379A",
    ]

    @assert(complexitySum(sampleCodes, 2) == 126_384'u64)
}
