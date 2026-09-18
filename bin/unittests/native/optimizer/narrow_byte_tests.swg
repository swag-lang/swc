#global private

// Character tests read a byte zero-extended to 32 bits. A shift by it reads
// the byte itself, and an unsigned test against a constant, or a range that
// fits the byte, tests the byte. Every byte must answer as the wide tests do.

#[Swag.Optimize(true), Swag.NoInline]
func isSpace(c: u8)->bool => c == ' ' or c == '\t' or c == '\n' or c == '\r'
#[Swag.Optimize(true), Swag.NoInline]
func isDigit(c: u8)->bool => c >= '0' and c <= '9'
#[Swag.Optimize(true), Swag.NoInline]
func isUpper(c: u8)->bool => c >= 'A' and c <= 'Z'
#[Swag.Optimize(true), Swag.NoInline]
func isHigh(c: u8)->bool => c > 200
#[Swag.Optimize(true), Swag.NoInline]
func isWideRange(c: u8)->bool => c >= 10 and c <= 250
#[Swag.Optimize(true), Swag.NoInline]
func shiftBy(x: u64, c: u8)->u64 => x >> (c & 63)
#[Swag.Optimize(true), Swag.NoInline]
func hexValue(c: u8)->s32
{
    if c >= '0' and c <= '9' do
        return cast(s32) (c - '0')
    if c >= 'a' and c <= 'f' do
        return cast(s32) (c - 'a') + 10
    return -1
}

#[Swag.Optimize(false), Swag.NoInline]
func wide(c: u8)->u32 => cast(u32) c

#test
{
    for i in 256
    {
        let c = cast(u8) i
        let w = wide(c)
        Swag.assert(isSpace(c) == (w == 32 or w == 9 or w == 10 or w == 13))
        Swag.assert(isDigit(c) == (w >= 48 and w <= 57))
        Swag.assert(isUpper(c) == (w >= 65 and w <= 90))
        Swag.assert(isHigh(c) == (w > 200))
        Swag.assert(isWideRange(c) == (w >= 10 and w <= 250))
        Swag.assert(shiftBy(0x8000000000000000, c) == 0x8000000000000000'u64 >> (w & 63))
        let expected = w >= 48 and w <= 57 ? cast(s32) w - 48 : (w >= 97 and w <= 102 ? cast(s32) w - 87 : -1)
        Swag.assert(hexValue(c) == expected)
    }
}
