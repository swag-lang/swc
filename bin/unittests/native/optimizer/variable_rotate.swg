#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func left(a, b: u64)->u64 => (a << (b & 63)) | (a >> ((0 - b) & 63))
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func right(a, b: u64)->u64 => (a >> (b & 63)) | (a << ((0 - b) & 63))
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func left32(a, b: u32)->u32 => (a << (b & 31)) | (a >> ((0 - b) & 31))
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func right32(a, b: u32)->u32 => (a >> (b & 31)) | (a << ((0 - b) & 31))
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func shared(a, b: u64)->u64
{
    let shifted = a << (b & 63)
    return (shifted | (a >> ((0 - b) & 63))) ^ shifted
}
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func compared(a, b: u64)->bool => ((a << (b & 63)) | (a >> ((0 - b) & 63))) == 0
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func different(a, b, c: u64)->u64 => (a << (b & 63)) | (c >> ((0 - b) & 63))
#[Swag.NoInline]
func shiftLeft(a, b: u64)->u64 => a << b
#[Swag.NoInline]
func shiftRight(a, b: u64)->u64 => a >> b
#[Swag.NoInline]
func oracle(a, b: u64)->u64
{
    var value = a
    var count = b & 63
    while count != 0
    {
        value = (value << 1) | (value >> 63)
        count -= 1
    }
    return value
}
#[Swag.NoInline]
func oracle32(a, b: u32)->u32
{
    var value = a
    var count = b & 31
    while count != 0
    {
        value = (value << 1) | (value >> 31)
        count -= 1
    }
    return value
}

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xABCDEF0123456789, 0xFFFFFFFFFFFFFFFF]
    let counts = [0'u64, 1, 7, 31, 32, 33, 63, 64, 65, 127, 128, 255, 0x100000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        for b in counts
        {
            let opposite = 0'u64 - b
            Swag.assert(left(a, b) == oracle(a, b))
            Swag.assert(right(a, b) == oracle(a, opposite))
            Swag.assert(shared(a, b) == (oracle(a, b) ^ shiftLeft(a, b & 63)))
            Swag.assert(compared(a, b) == (a == 0))
            Swag.assert(different(a, b, ~a) == (shiftLeft(a, b & 63) | shiftRight(~a, opposite & 63)))
            let lowA = cast(u32) (a & 0xFFFFFFFF)
            let lowB = cast(u32) (b & 0xFFFFFFFF)
            Swag.assert(left32(lowA, lowB) == oracle32(lowA, lowB))
            Swag.assert(right32(lowA, lowB) == oracle32(lowA, 0'u32 - lowB))
        }
    }
}
