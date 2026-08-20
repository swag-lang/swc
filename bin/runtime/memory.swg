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
        offset           += 4 * MemoryVectorSize
    }

    while size - offset >= MemoryVectorSize
    {
        let sourceVector = (source + offset)[as MemoryVector]
        (target + offset)[as MemoryVector] = sourceVector
        offset += MemoryVectorSize
    }

    while size - offset >= MemoryWordSize
    {
        (target + offset)[as u64] = (source + offset)[as u64]
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
        let sourceVector = (source + offset)[as MemoryVector]
        (target + offset)[as MemoryVector] = sourceVector
    }

    while offset >= MemoryWordSize
    {
        offset -= MemoryWordSize
        (target + offset)[as u64] = (source + offset)[as u64]
    }

    while offset
    {
        offset         -= 1
        target[offset] = source[offset]
    }
}

func @memset(dst: #null [*] void, value: u8, size: u64)
{
    if !size do
        return

    let target = cast([*] u8) dst!
    var offset = 0'u64

    let word   = cast(u64) value * 0x0101_0101_0101_0101
    let vector = @vecsplat(word)
    while size - offset >= 4 * MemoryVectorSize
    {
        let targetVectors = cast([*] MemoryFillVector) (target + offset)
        targetVectors[0] = vector
        targetVectors[1] = vector
        targetVectors[2] = vector
        targetVectors[3] = vector
        offset           += 4 * MemoryVectorSize
    }

    while size - offset >= MemoryVectorSize
    {
        (target + offset)[as MemoryFillVector] = vector
        offset += MemoryVectorSize
    }

    while size - offset >= MemoryWordSize
    {
        (target + offset)[as u64] = word
        offset += MemoryWordSize
    }

    while offset < size
    {
        target[offset] = value
        offset         += 1
    }
}

func @memcpy(dst: #null [*] void, src: #null const [*] void, size: u64)
{
    if size do
        __memoryCopyForward(cast([*] u8) dst!, cast(const [*] u8) src!, size)
}

func @memmove(dst: #null [*] void, src: #null const [*] void, size: u64)
{
    if !size or dst == src do
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

func @memcmp(left, right: #null const [*] void, size: u64)->s32
{
    if !size do
        return 0

    let leftBytes  = cast(const [*] u8) left!
    let rightBytes = cast(const [*] u8) right!
    var offset     = 0'u64
    while size - offset >= MemoryVectorSize
    {
        let leftVector  = (leftBytes + offset)[as MemoryVector]
        let rightVector = (rightBytes + offset)[as MemoryVector]
        if @vecmask(leftVector == rightVector) != 0xFFFF
        {
            for index in MemoryVectorSize
            {
                if leftBytes[offset + index] != rightBytes[offset + index] do
                    return cast(s32) leftBytes[offset + index] - cast(s32) rightBytes[offset + index]
            }
        }

        offset += MemoryVectorSize
    }

    while size - offset >= MemoryWordSize
    {
        let leftWord  = (leftBytes + offset)[as u64]
        let rightWord = (rightBytes + offset)[as u64]
        if leftWord != rightWord
        {
            for index in MemoryWordSize
            {
                if leftBytes[offset + index] != rightBytes[offset + index] do
                    return cast(s32) leftBytes[offset + index] - cast(s32) rightBytes[offset + index]
            }
        }

        offset += MemoryWordSize
    }

    while offset < size
    {
        if leftBytes[offset] != rightBytes[offset] do
            return cast(s32) leftBytes[offset] - cast(s32) rightBytes[offset]
        offset += 1
    }

    return 0
}
