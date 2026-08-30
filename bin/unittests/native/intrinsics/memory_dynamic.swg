#global private

#[Swag.NoInline]
func fillDynamic(target: #null [*] void, value: u8, size: u64)
{
    Swag.memset(target, value, size)
}

#[Swag.NoInline]
func copyDynamic(target: #null [*] void, source: #null const [*] void, size: u64)
{
    Swag.memcpy(target, source, size)
}

#[Swag.NoInline]
func moveDynamic(target: #null [*] void, source: #null const [*] void, size: u64)
{
    Swag.memmove(target, source, size)
}

#[Swag.NoInline]
func compareDynamic(left, right: #null const [*] void, size: u64)->s32
{
    return Swag.memcmp(left, right, size)
}

#test
{
    var source: [17] u8
    var target: [17] u8
    for &value, index in source do
        value[] = cast(u8) (index + 1)

    fillDynamic(target, 0xA5, #sizeof(target))
    for value in target do
        Swag.assert(value == 0xA5)

    copyDynamic(target, source, #sizeof(target))
    Swag.assert(compareDynamic(target, source, #sizeof(target)) == 0)

    target[8] = 0
    Swag.assert(compareDynamic(target, source, #sizeof(target)) < 0)
    target[8] = 0xFF
    Swag.assert(compareDynamic(target, source, #sizeof(target)) > 0)
}

#test
{
    var data: [10] u8 = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
    moveDynamic(&data[2], &data[0], 7)
    Swag.assert(data == [0, 1, 0, 1, 2, 3, 4, 5, 6, 9])

    moveDynamic(&data[0], &data[2], 7)
    Swag.assert(data == [0, 1, 2, 3, 4, 5, 6, 5, 6, 9])

    moveDynamic(&data[0], &data[0], #sizeof(data))
    fillDynamic(null, 0, 0)
    copyDynamic(null, null, 0)
    moveDynamic(null, null, 0)
    Swag.assert(compareDynamic(null, null, 0) == 0)
}

#test
{
    var data: [96] u8
    for &value, index in data do
        value[] = cast(u8) index

    moveDynamic(&data[8], &data[0], 80)
    for index in 80 do
        Swag.assert(data[8 + index] == cast(u8) index)

    for &value, index in data do
        value[] = cast(u8) index
    moveDynamic(&data[0], &data[8], 80)
    for index in 80 do
        Swag.assert(data[index] == cast(u8) (index + 8))
}

// Dynamic sizes and every alignment around a vector boundary preserve guards,
// ordering, and memmove's snapshot semantics.
#test
{
    const Capacity = 160
    var source:   [Capacity] u8
    var target:   [Capacity] u8
    var expected: [Capacity] u8

    for i in Capacity do
        source[i] = cast(u8) ((i * 37 + 11) & 0xFF)

    for size in 65
    {
        for sourceOffset in 16
        {
            let targetOffset = 16 - sourceOffset
            fillDynamic(target, 0xCD, Capacity)
            copyDynamic(&target[targetOffset], &source[sourceOffset], size)
            for i in Capacity
            {
                let inside = i >= targetOffset and i < targetOffset + size
                Swag.assert(target[i] == (inside ? source[sourceOffset + i - targetOffset] : 0xCD))
            }

            Swag.assert(compareDynamic(&target[targetOffset], &source[sourceOffset], size) == 0)
            if size
            {
                target[targetOffset + size - 1] ^= 0xFF
                Swag.assert(compareDynamic(&target[targetOffset], &source[sourceOffset], size) != 0)
            }
        }
    }

    for distance in 1 to 17
    {
        for size in 65
        {
            for i in Capacity
            {
                target[i]   = cast(u8) i
                expected[i] = cast(u8) i
            }

            for i in size do
                expected[32 + distance + i] = cast(u8) (32 + i)
            moveDynamic(&target[32 + distance], &target[32], size)
            Swag.assert(compareDynamic(target, expected, Capacity) == 0)

            for i in Capacity
            {
                target[i]   = cast(u8) i
                expected[i] = cast(u8) i
            }
            for i in size do
                expected[32 + i] = cast(u8) (32 + distance + i)
            moveDynamic(&target[32], &target[32 + distance], size)
            Swag.assert(compareDynamic(target, expected, Capacity) == 0)
        }
    }
}
