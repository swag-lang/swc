#global private

#[Swag.NoInline] func shiftLeft8(value, first, second, flag: u8)->u8 => flag != 0 ? value << first : value << second
#[Swag.NoInline] func shiftRight16(value, first, second, flag: u16)->u16 => flag != 0 ? value >> first : value >> second

#test
{
    let values = [0'u32, 1, 0x7F, 0x80, 0xFF, 0x1234, 0x8000, 0xFFFF]
    let counts = [0'u32, 1, 7, 8, 15, 16, 31, 32, 63, 255]
    for value in values do for first in counts do for second in counts do for flag in [0'u32, 1, 255]
    {
        let value8 = cast(u8) value
        let first8 = cast(u8) first
        let second8 = cast(u8) second
        let flag8 = cast(u8) flag
        Swag.assert(shiftLeft8(value8, first8, second8, flag8) == (flag8 != 0 ? value8 << first8 : value8 << second8))

        let value16 = cast(u16) value
        let first16 = cast(u16) first
        let second16 = cast(u16) second
        let flag16 = cast(u16) flag
        Swag.assert(shiftRight16(value16, first16, second16, flag16) == (flag16 != 0 ? value16 >> first16 : value16 >> second16))
    }
}
