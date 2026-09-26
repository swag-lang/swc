// Runtime fallbacks for dynamic memory-block intrinsics. Constant sizes are lowered inline by
// the compiler and never reach these functions.

const MemoryWordSize = #sizeof(u64)
alias MemoryVector     = #simd [16] u8
alias MemoryFillVector = #simd [2] u64
const MemoryVectorSize = #sizeof(MemoryVector)

func __memoryCopyForward(target: [*] u8, source: const [*] u8, size: u64)
{
    var offset = 0'u64
    while size - offset >= 4 * MemoryVectorSize
    {
        let targetVectors = cast([*] MemoryVector) (target + offset)
        let sourceVectors = cast(const [*] MemoryVector) (source + offset)
        let source0       = sourceVectors[0]
        let source1       = sourceVectors[1]
        let source2       = sourceVectors[2]
        let source3       = sourceVectors[3]
        targetVectors[0] = source0
        targetVectors[1] = source1
        targetVectors[2] = source2
        targetVectors[3] = source3
        offset += 4 * MemoryVectorSize
    }

    while size - offset >= MemoryVectorSize
    {
        let sourceVector = (cast(const *MemoryVector) (source + offset))[]
        (cast(*MemoryVector) (target + offset))[] = sourceVector
        offset += MemoryVectorSize
    }

    while size - offset >= MemoryWordSize
    {
        (cast(*u64) (target + offset))[] = (cast(const *u64) (source + offset))[]
        offset += MemoryWordSize
    }

    while offset < size
    {
        target[offset] = source[offset]
        offset         += 1
    }
}

func __memoryCopyBackward(target: [*] u8, source: const [*] u8, size: u64)
{
    var offset = size
    while offset >= 4 * MemoryVectorSize
    {
        offset -= 4 * MemoryVectorSize
        let targetVectors = cast([*] MemoryVector) (target + offset)
        let sourceVectors = cast(const [*] MemoryVector) (source + offset)
        let source0       = sourceVectors[0]
        let source1       = sourceVectors[1]
        let source2       = sourceVectors[2]
        let source3       = sourceVectors[3]
        targetVectors[3] = source3
        targetVectors[2] = source2
        targetVectors[1] = source1
        targetVectors[0] = source0
    }

    while offset >= MemoryVectorSize
    {
        offset -= MemoryVectorSize
        let sourceVector = (cast(const *MemoryVector) (source + offset))[]
        (cast(*MemoryVector) (target + offset))[] = sourceVector
    }

    while offset >= MemoryWordSize
    {
        offset -= MemoryWordSize
        (cast(*u64) (target + offset))[] = (cast(const *u64) (source + offset))[]
    }

    while offset
    {
        offset         -= 1
        target[offset] = source[offset]
    }
}

func memset(dst: [*] void?, value: u8, size: u64)
{
    if not size do
        return

    let target = cast([*] u8) dst!
    var offset = 0'u64

    let word   = cast(u64) value * 0x0101_0101_0101_0101
    let vector = Swag.vecsplat(word)
    while size - offset >= 4 * MemoryVectorSize
    {
        let targetVectors = cast([*] MemoryFillVector) (target + offset)
        targetVectors[0] = vector
        targetVectors[1] = vector
        targetVectors[2] = vector
        targetVectors[3] = vector
        offset += 4 * MemoryVectorSize
    }

    while size - offset >= MemoryVectorSize
    {
        (cast(*MemoryFillVector) (target + offset))[] = vector
        offset += MemoryVectorSize
    }

    while size - offset >= MemoryWordSize
    {
        (cast(*u64) (target + offset))[] = word
        offset += MemoryWordSize
    }

    while offset < size
    {
        target[offset] = value
        offset         += 1
    }
}

func memcpy(dst: [*] void?, src: const [*] void?, size: u64)
{
    if size do
        __memoryCopyForward(cast([*] u8) dst!, cast(const [*] u8) src!, size)
}

func memmove(dst: [*] void?, src: const [*] void?, size: u64)
{
    if not size or dst == src do
        return

    let target        = cast([*] u8) dst!
    let source        = cast(const [*] u8) src!
    let targetAddress = cast(u64) target
    let sourceAddress = cast(u64) source
    if targetAddress < sourceAddress or targetAddress - sourceAddress >= size do
        __memoryCopyForward(target, source, size)
    else do
        __memoryCopyBackward(target, source, size)
}

#[Swag.ReadOnly]
func memcmp(left, right: const [*] void?, size: u64)->s32
{
    if not size do
        return 0

    let leftBytes  = cast(const [*] u8) left!
    let rightBytes = cast(const [*] u8) right!
    var offset     = 0'u64
    while size - offset >= MemoryVectorSize
    {
        let leftVector  = (cast(const *MemoryVector) (leftBytes + offset))[]
        let rightVector = (cast(const *MemoryVector) (rightBytes + offset))[]
        let equalMask = Swag.vecmask(leftVector == rightVector)
        if equalMask != 0xFFFF
        {
            // The lowest clear mask bit is the first byte that differs.
            let index = cast(u64) Swag.bitCountTz((~equalMask) & 0xFFFF)
            return cast(s32) leftBytes[offset + index] - cast(s32) rightBytes[offset + index]
        }

        offset += MemoryVectorSize
    }

    while size - offset >= MemoryWordSize
    {
        let leftWord  = (cast(const *u64) (leftBytes + offset))[]
        let rightWord = (cast(const *u64) (rightBytes + offset))[]
        let difference = leftWord ^ rightWord
        if difference
        {
            // On the supported little-endian target, the lowest set bit names the first byte.
            let index = Swag.bitCountTz(difference) / 8
            return cast(s32) leftBytes[offset + index] - cast(s32) rightBytes[offset + index]
        }

        offset += MemoryWordSize
    }

    if size - offset >= 4
    {
        let leftPart   = (cast(const *u32) (leftBytes + offset))[]
        let rightPart  = (cast(const *u32) (rightBytes + offset))[]
        let difference = leftPart ^ rightPart
        if difference
        {
            let index = cast(u64) Swag.bitCountTz(difference) / 8
            return cast(s32) leftBytes[offset + index] - cast(s32) rightBytes[offset + index]
        }
        offset += 4
    }

    if size - offset >= 2
    {
        let leftPart   = (cast(const *u16) (leftBytes + offset))[]
        let rightPart  = (cast(const *u16) (rightBytes + offset))[]
        let difference = leftPart ^ rightPart
        if difference
        {
            let index = cast(u64) Swag.bitCountTz(difference) / 8
            return cast(s32) leftBytes[offset + index] - cast(s32) rightBytes[offset + index]
        }
        offset += 2
    }

    if offset < size
    {
        if leftBytes[offset] != rightBytes[offset] do
            return cast(s32) leftBytes[offset] - cast(s32) rightBytes[offset]
    }

    return 0
}
