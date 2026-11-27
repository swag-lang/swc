#global private

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
    return y >= 0 and y < 4 and x >= 0 and x < 3 and not (x == 0 and y == 3)
}

func isDirectionalKey(x, y: s32)->bool
{
    return y >= 0 and y < 2 and x >= 0 and x < 3 and not (x == 0 and y == 0)
}

func numericPos(key: u8)->KeyPos
{
    switch key
    {
    case '7'_u8: return KeyPos{0, 0}
    case '8'_u8: return KeyPos{1, 0}
    case '9'_u8: return KeyPos{2, 0}
    case '4'_u8: return KeyPos{0, 1}
    case '5'_u8: return KeyPos{1, 1}
    case '6'_u8: return KeyPos{2, 1}
    case '1'_u8: return KeyPos{0, 2}
    case '2'_u8: return KeyPos{1, 2}
    case '3'_u8: return KeyPos{2, 2}
    case '0'_u8: return KeyPos{1, 3}
    case 'A'_u8: return KeyPos{2, 3}
    default:
        Swag.assert(false)
        return KeyPos{0, 0}
    }
}

func directionalPos(key: u8)->KeyPos
{
    switch key
    {
    case '^'_u8: return KeyPos{1, 0}
    case 'A'_u8: return KeyPos{2, 0}
    case '<'_u8: return KeyPos{0, 1}
    case 'v'_u8: return KeyPos{1, 1}
    case '>'_u8: return KeyPos{2, 1}
    default:
        Swag.assert(false)
        return KeyPos{0, 0}
    }
}

func directionalKeyIndex(key: u8)->u32
{
    switch key
    {
    case '^'_u8: return 0
    case 'A'_u8: return 1
    case '<'_u8: return 2
    case 'v'_u8: return 3
    case '>'_u8: return 4
    default:
        Swag.assert(false)
        return 0
    }
}

func absValue(value: s32)->u32
{
    if value < 0
    {
        return cast(u32, (-value))
    }
    return cast(u32, value)
}

func buildPath(outPath: *PathBuffer, fromPos, toPos: KeyPos, directionalPad: bool, horizontalFirst: bool)->bool
{
    var path: PathBuffer
    var x  = fromPos.x
    var y  = fromPos.y
    let dx = toPos.x - fromPos.x
    let dy = toPos.y - fromPos.y

    var horizontalMove = '>'_u8
    if dx < 0
    {
        horizontalMove = '<'_u8
    }

    var verticalMove = 'v'_u8
    if dy < 0
    {
        verticalMove = '^'_u8
    }
    let horizontalCount = absValue(dx)
    let verticalCount   = absValue(dy)

    var firstMove   = horizontalMove
    var firstCount  = horizontalCount
    var secondMove  = verticalMove
    var secondCount = verticalCount

    if not horizontalFirst
    {
        firstMove   = verticalMove
        firstCount  = verticalCount
        secondMove  = horizontalMove
        secondCount = horizontalCount
    }

    for firstCount
    {
        switch firstMove
        {
        case '<'_u8: x -= 1
        case '>'_u8: x += 1
        case '^'_u8: y -= 1
        case 'v'_u8: y += 1
        default:     Swag.assert(false)
        }

        if directionalPad
        {
            if not isDirectionalKey(x, y)
            {
                return false
            }
        }
        else
        {
            if not isNumericKey(x, y)
            {
                return false
            }
        }

        path.buttons[path.count] = firstMove
        path.count += 1
    }

    for secondCount
    {
        switch secondMove
        {
        case '<'_u8: x -= 1
        case '>'_u8: x += 1
        case '^'_u8: y -= 1
        case 'v'_u8: y += 1
        default:     Swag.assert(false)
        }

        if directionalPad
        {
            if not isDirectionalKey(x, y)
            {
                return false
            }
        }
        else
        {
            if not isNumericKey(x, y)
            {
                return false
            }
        }

        path.buttons[path.count] = secondMove
        path.count += 1
    }

    path.buttons[path.count] = 'A'_u8
    path.count += 1
    outPath[]  = path
    return true
}

func sequenceCost(path: PathBuffer, depth: u32)->u64
{
    if depth == 0
    {
        return cast(u64, path.count)
    }

    var total: u64
    var current = 'A'_u8

    for index in path.count
    {
        let next      = path.buttons[index]
        let fromIndex = directionalKeyIndex(current)
        let toIndex   = directionalKeyIndex(next)
        let cached    = DirectionalMemo[depth][fromIndex][toIndex]

        if cached != 0
        {
            total += cached
        }
        else
        {
            let fromPos = directionalPos(current)
            let toPos   = directionalPos(next)
            var candidateA: PathBuffer
            var candidateB: PathBuffer
            var best    = Swag.U64.Max

            if buildPath(&candidateA, fromPos, toPos, true, true)
            {
                let value = sequenceCost(candidateA, depth - 1)
                if value < best
                {
                    best = value
                }
            }

            if buildPath(&candidateB, fromPos, toPos, true, false)
            {
                let value = sequenceCost(candidateB, depth - 1)
                if value < best
                {
                    best = value
                }
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
    let bytes = cast(const [..] u8, code)
    var value: u64

    for ch in bytes
    {
        if ch == 'A'_u8
        {
            break
        }
        value = value * 10_u64 + cast(u64, (ch - '0'_u8))
    }

    return value
}

func codePressCount(code: string, depth: u32)->u64
{
    let bytes   = cast(const [..] u8, code)
    var total: u64
    var current = 'A'_u8

    for next in bytes
    {
        let fromPos = numericPos(current)
        let toPos   = numericPos(next)
        var candidateA: PathBuffer
        var candidateB: PathBuffer
        var best    = Swag.U64.Max

        if buildPath(&candidateA, fromPos, toPos, false, true)
        {
            let value = sequenceCost(candidateA, depth)
            if value < best
            {
                best = value
            }
        }

        if buildPath(&candidateB, fromPos, toPos, false, false)
        {
            let value = sequenceCost(candidateB, depth)
            if value < best
            {
                best = value
            }
        }

        total   += best
        current = next
    }

    return total
}

func complexitySum(codes: const [..] string, depth: u32)->u64
{
    var total: u64

    for code in codes
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
        "379A"
        ]

    Swag.require(complexitySum(sampleCodes, 2) == 126_384_u64)
}
