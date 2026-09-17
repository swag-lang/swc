#global private

// Loops that compare indexed memory with a byte, word or dword parameter
// keep the parameter in its register instead of a narrowed copy. Every
// element width and a value found at both ends must still count right.

#[Swag.Optimize(true), Swag.NoInline]
func countByte(data: const [*] u8, count: u64, value: u8)->u64
{
    var total = 0'u64
    for i in count
    {
        if data[i] == value do
            total += 1
    }
    return total
}

#[Swag.Optimize(true), Swag.NoInline]
func countWord(data: const [*] u16, count: u64, value: u16)->u64
{
    var total = 0'u64
    for i in count
    {
        if data[i] == value do
            total += 1
    }
    return total
}

#[Swag.Optimize(true), Swag.NoInline]
func lastBelow(data: const [*] s32, count: u64, limit: s32)->s64
{
    var i = cast(s64) count - 1
    while i >= 0
    {
        if data[i] < limit do
            return i
        i -= 1
    }
    return -1
}

#test
{
    var bytes: [6] u8 = [7, 200, 7, 0, 255, 7]
    Swag.assert(countByte(&bytes[0], 6, 7) == 3)
    Swag.assert(countByte(&bytes[0], 6, 255) == 1)
    Swag.assert(countByte(&bytes[0], 6, 1) == 0)

    var words: [5] u16 = [0x1234, 0xFFFF, 0x1234, 0x34, 0x1200]
    Swag.assert(countWord(&words[0], 5, 0x1234) == 2)
    Swag.assert(countWord(&words[0], 5, 0x34) == 1)
    Swag.assert(countWord(&words[0], 5, 0xFFFF) == 1)

    var ints: [5] s32 = [-5, 10, 3, 20, 30]
    Swag.assert(lastBelow(&ints[0], 5, 5) == 2)
    Swag.assert(lastBelow(&ints[0], 5, -5) == -1)
    Swag.assert(lastBelow(&ints[0], 5, 100) == 4)
}
