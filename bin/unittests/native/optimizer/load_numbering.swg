#global private

// The byte a scanner compares is the byte it consumes: value numbering feeds
// both from one load. Every case below checks the value, and that a write in
// between — a store, a call — is still honoured by a fresh load.

#[Swag.Optimize(true)]
func parseDigits(text: [*] u8, start, eol: u64)->u64
{
    var p   = start
    var qty = 0'u64
    while p < eol and text[p] != ','
    {
        qty = qty * 10 + cast(u64) (text[p] - 48)
        p   += 1
    }

    return qty
}

#[Swag.Optimize(true)]
func sameCellTwice(buf: [*] s32)->s32
{
    return buf[2] + buf[2]
}

#[Swag.Optimize(true)]
func storeBetweenLoads(buf: [*] s32)->s32
{
    let a = buf[0]
    buf[0] = a + 5
    let b = buf[0]
    return b - a
}

#[Swag.NoInline]
func bump(buf: [*] s32)
{
    buf[1] += 1
}

#[Swag.Optimize(true)]
func callBetweenLoads(buf: [*] s32)->s32
{
    let a = buf[1]
    bump(buf)
    let b = buf[1]
    return b - a
}

#[Swag.Optimize(true)]
func storeThroughOtherPointer(buf, other: [*] s32)->s32
{
    let a = buf[3]
    other[0] = a + 7
    let b = buf[3]
    return b - a
}

#test
{
    var digits: [8] u8 = ['1', '2', '3', ',', '4', '5', '\n', 0]
    Swag.assert(parseDigits(&digits[0], 0, 7) == 123)
    Swag.assert(parseDigits(&digits[0], 4, 6) == 45)

    var buf: [4] s32 = [10, 20, 30, 40]
    Swag.assert(sameCellTwice(&buf[0]) == 60)
    Swag.assert(storeBetweenLoads(&buf[0]) == 5)
    Swag.assert(buf[0] == 15)
    Swag.assert(callBetweenLoads(&buf[0]) == 1)
    Swag.assert(buf[1] == 21)
    Swag.assert(storeThroughOtherPointer(&buf[0], &buf[3]) == 7)
    Swag.assert(buf[3] == 47)
}
