// Runtime fallbacks for dynamic memory-block intrinsics. Constant sizes are lowered inline by
// the compiler and never reach these functions.

const MemoryWordSize = #sizeof(u64)
const MemoryWordMask = MemoryWordSize - 1
alias MemoryVector = [2] u64
const MemoryVectorSize = #sizeof(MemoryVector)

func __memoryCopyForward(target: [*] u8, source: const [*] u8, size: u64)
{
    var offset        = 0'u64
    let targetAddress = cast(u64) target
    let sourceAddress = cast(u64) source
    if !((targetAddress ^ sourceAddress) & MemoryWordMask)
    {
        while offset < size and (targetAddress + offset) & MemoryWordMask
        {
            target[offset] = source[offset]
            offset         += 1
        }

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
            let sourceVector = (cast(const *MemoryVector) (source + offset))[]
            (cast(*MemoryVector) (target + offset))[] = sourceVector
            offset += MemoryVectorSize
        }

        while size - offset >= MemoryWordSize
        {
            (cast(*u64) (target + offset))[] = (cast(const *u64) (source + offset))[]
            offset += MemoryWordSize
        }
    }

    while offset < size
    {
        target[offset] = source[offset]
        offset         += 1
    }
}

func __memoryCopyBackward(target: [*] u8, source: const [*] u8, size: u64)
{
    var offset        = size
    let targetAddress = cast(u64) target
    let sourceAddress = cast(u64) source
    if !((targetAddress ^ sourceAddress) & MemoryWordMask)
    {
        while offset and (targetAddress + offset) & MemoryWordMask
        {
            offset         -= 1
            target[offset] = source[offset]
        }

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

    let target        = cast([*] u8) dst!
    let targetAddress = cast(u64) target
    var offset        = 0'u64
    while offset < size and (targetAddress + offset) & MemoryWordMask
    {
        target[offset] = value
        offset         += 1
    }

    let word                 = cast(u64) value * 0x0101_0101_0101_0101
    let vector: MemoryVector = [word, word]
    while size - offset >= 4 * MemoryVectorSize
    {
        let targetVectors = cast([*] MemoryVector) (target + offset)
        targetVectors[0] = vector
        targetVectors[1] = vector
        targetVectors[2] = vector
        targetVectors[3] = vector
        offset           += 4 * MemoryVectorSize
    }

    while size - offset >= MemoryVectorSize
    {
        (cast(*MemoryVector) (target + offset))[] = vector
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

    let leftBytes    = cast(const [*] u8) left!
    let rightBytes   = cast(const [*] u8) right!
    let leftAddress  = cast(u64) leftBytes
    let rightAddress = cast(u64) rightBytes
    var offset       = 0'u64
    if !((leftAddress ^ rightAddress) & MemoryWordMask)
    {
        while offset < size and (leftAddress + offset) & MemoryWordMask
        {
            if leftBytes[offset] != rightBytes[offset] do
                return cast(s32) leftBytes[offset] - cast(s32) rightBytes[offset]
            offset += 1
        }

        while size - offset >= MemoryWordSize
        {
            let leftWord  = (cast(const *u64) (leftBytes + offset))[]
            let rightWord = (cast(const *u64) (rightBytes + offset))[]
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
    }

    while offset < size
    {
        if leftBytes[offset] != rightBytes[offset] do
            return cast(s32) leftBytes[offset] - cast(s32) rightBytes[offset]
        offset += 1
    }

    return 0
}
