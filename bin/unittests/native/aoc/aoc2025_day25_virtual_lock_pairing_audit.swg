#global private

// Real-life example: screen a batch of virtual five-pin lock schematics against
// key schematics and count how many combinations can fit without overlap.

const SchematicWidth  = 5
const SchematicHeight = 7
const MaxColumnHeight = SchematicHeight - 2

struct PinProfile
{
    heights: [SchematicWidth] u32
}

struct PairingAudit
{
    lockCount:           u32
    keyCount:            u32
    compatiblePairCount: u32
}

func lineWidth(line: string)->u32
{
    return cast(u32) (cast(const [..] u8) line).count
}

func filledAt(schematic: const [..] string, row, column: u32)->bool
{
    let bytes = cast(const [..] u8) schematic[row]
    return bytes[column] == '#'u8
}

func rowIsFilledWith(schematic: const [..] string, row: u32, ch: u8)->bool
{
    let bytes = cast(const [..] u8) schematic[row]
    Swag.assert(bytes.count == SchematicWidth)

    for SchematicWidth
    {
        let column = cast(u32) Swag.index
        if bytes[column] != ch do
            return false
    }

    return true
}

func isLockSchematic(schematic: const [..] string)->bool
{
    return rowIsFilledWith(schematic, 0, '#'u8) and rowIsFilledWith(schematic, SchematicHeight - 1, '.'u8)
}

func isKeySchematic(schematic: const [..] string)->bool
{
    return rowIsFilledWith(schematic, 0, '.'u8) and rowIsFilledWith(schematic, SchematicHeight - 1, '#'u8)
}

func profileFromSchematic(schematic: const [..] string)->PinProfile
{
    Swag.assert(schematic.count == SchematicHeight)

    var result: PinProfile

    for SchematicHeight
    {
        Swag.assert(lineWidth(schematic[Swag.index]) == SchematicWidth)
    }

    for SchematicWidth
    {
        let column = cast(u32) Swag.index
        var filledCount: u32

        for SchematicHeight
        {
            let row = cast(u32) Swag.index
            if filledAt(schematic, row, column) do
                filledCount += 1
        }

        Swag.assert(filledCount >= 1 and filledCount <= SchematicHeight - 1)
        result.heights[column] = filledCount - 1
        Swag.assert(result.heights[column] <= MaxColumnHeight)
    }

    return result
}

func fits(lockProfile, keyProfile: PinProfile)->bool
{
    for SchematicWidth
    {
        let column = cast(u32) Swag.index
        if lockProfile.heights[column] + keyProfile.heights[column] > MaxColumnHeight do
            return false
    }

    return true
}

func auditPairings(lockProfiles: const [..] PinProfile, keyProfiles: const [..] PinProfile)->PairingAudit
{
    var result: PairingAudit
    result.lockCount = cast(u32) lockProfiles.count
    result.keyCount  = cast(u32) keyProfiles.count

    for lockProfile in lockProfiles
    {
        for keyProfile in keyProfiles
        {
            if fits(lockProfile, keyProfile) do
                result.compatiblePairCount += 1
        }
    }

    return result
}

#test
{
    const lock0: [7] string =
        [
        "#####",
        ".####",
        ".####",
        ".####",
        ".#.#.",
        ".#...",
        "....."
        ]

    const lock1: [7] string =
        [
        "#####",
        "##.##",
        ".#.##",
        "...##",
        "...#.",
        "...#.",
        "....."
        ]

    const key0: [7] string =
        [
        ".....",
        "#....",
        "#....",
        "#...#",
        "#.#.#",
        "#.###",
        "#####"
        ]

    const key1: [7] string =
        [
        ".....",
        ".....",
        "#.#..",
        "###..",
        "###.#",
        "###.#",
        "#####"
        ]

    const key2: [7] string =
        [
        ".....",
        ".....",
        ".....",
        "#....",
        "#.#..",
        "#.#.#",
        "#####"
        ]

    Swag.assert(isLockSchematic(lock0))
    Swag.assert(isLockSchematic(lock1))
    Swag.assert(isKeySchematic(key0))
    Swag.assert(isKeySchematic(key1))
    Swag.assert(isKeySchematic(key2))

    let lockProfile0 = profileFromSchematic(lock0)
    let lockProfile1 = profileFromSchematic(lock1)
    let keyProfile0  = profileFromSchematic(key0)
    let keyProfile1  = profileFromSchematic(key1)
    let keyProfile2  = profileFromSchematic(key2)

    Swag.assert(lockProfile0.heights[0] == 0)
    Swag.assert(lockProfile0.heights[1] == 5)
    Swag.assert(lockProfile0.heights[2] == 3)
    Swag.assert(lockProfile0.heights[3] == 4)
    Swag.assert(lockProfile0.heights[4] == 3)

    Swag.assert(keyProfile0.heights[0] == 5)
    Swag.assert(keyProfile0.heights[1] == 0)
    Swag.assert(keyProfile0.heights[2] == 2)
    Swag.assert(keyProfile0.heights[3] == 1)
    Swag.assert(keyProfile0.heights[4] == 3)

    Swag.assert(!fits(lockProfile0, keyProfile0))
    Swag.assert(!fits(lockProfile0, keyProfile1))
    Swag.assert(fits(lockProfile0, keyProfile2))
    Swag.assert(!fits(lockProfile1, keyProfile0))
    Swag.assert(fits(lockProfile1, keyProfile1))
    Swag.assert(fits(lockProfile1, keyProfile2))

    var sampleLocks: [2] PinProfile
    sampleLocks[0] = lockProfile0
    sampleLocks[1] = lockProfile1

    var sampleKeys: [3] PinProfile
    sampleKeys[0] = keyProfile0
    sampleKeys[1] = keyProfile1
    sampleKeys[2] = keyProfile2

    let sampleAudit = auditPairings(sampleLocks, sampleKeys)

    Swag.assert(sampleAudit.lockCount == 2)
    Swag.assert(sampleAudit.keyCount == 3)
    Swag.assert(sampleAudit.compatiblePairCount == 3)
}
