#global fileprivate

// Real-life example: audit a safe-opening rotation sheet and count how many
// times the dial lands on zero during the sequence.

struct Rotation
{
    turnLeft: bool
    clicks:   s32
}

struct SafeAudit
{
    finalPosition:   s32
    zeroHits:        s32
    totalClicks:     s32
    longestRotation: s32
}

func maxS32(lhs, rhs: s32)->s32
{
    return lhs > rhs ? lhs : rhs
}

func wrapDial(position: s32)->s32
{
    var wrapped = position % 100
    if wrapped < 0 do
        wrapped += 100
    return wrapped
}

func parseRotation(text: string)->Rotation
{
    let bytes = cast(const [..] u8) text

    var result: Rotation
    result.turnLeft = bytes[0] == 'L'

    for i in 1 to cast(u32) @countof(bytes) - 1 do
        result.clicks = result.clicks * 10 + cast(s32) (bytes[i] - '0')

    return result
}

func auditRotations(lines: const [..] string, startPosition: s32)->SafeAudit
{
    var result: SafeAudit
    var current = startPosition

    foreach line in lines
    {
        let rotation = parseRotation(line)
        result.totalClicks += rotation.clicks
        result.longestRotation = maxS32(result.longestRotation, rotation.clicks)

        let signedClicks = rotation.turnLeft ? -rotation.clicks : rotation.clicks
        current = wrapDial(current + signedClicks)
        if current == 0 do
            result.zeroHits += 1
    }

    result.finalPosition = current
    return result
}

#test
{
    const entranceSheet: [10] string =
    [
        "L68",
        "L30",
        "R48",
        "L5",
        "R60",
        "L55",
        "L1",
        "L99",
        "R14",
        "L82",
    ]

    let entranceAudit = auditRotations(entranceSheet, 50)

    @assert(entranceAudit.zeroHits == 3)
    @assert(entranceAudit.finalPosition == 32)
    @assert(entranceAudit.totalClicks == 462)
    @assert(entranceAudit.longestRotation == 99)

    const cashRoomSheet: [6] string =
    [
        "R50",
        "L1",
        "R1",
        "R99",
        "L49",
        "L50",
    ]

    let cashRoomAudit = auditRotations(cashRoomSheet, 50)

    @assert(cashRoomAudit.zeroHits == 3)
    @assert(cashRoomAudit.finalPosition == 0)
    @assert(cashRoomAudit.totalClicks == 250)
    @assert(cashRoomAudit.longestRotation == 99)
}
