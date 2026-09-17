#global private

#[Swag.NoInline] func shiftLeft8(value, first, second, flag: u8)->u8 => flag != 0 ? value << first : value << second
#[Swag.NoInline] func shiftRight16(value, first, second, flag: u16)->u16 => flag != 0 ? value >> first : value >> second

#test
{
    let values = [0'u32, 1, 0x7F, 0x80, 0xFF, 0x1234, 0x8000, 0xFFFF]
    let counts = [0'u32, 1, 7, 8, 15, 16, 31, 32, 63, 255]
    // Shift counts stay below the width they shift: anywhere else a shift is
    // a runtime error under safety and unspecified without it.
    for value in values do for first in counts do for second in counts do for flag in [0'u32, 1, 255]
    {
        let value8 = cast #wrap (u8) value
        let first8 = cast #wrap (u8) first & 7
        let second8 = cast #wrap (u8) second & 7
        let flag8 = cast #wrap (u8) flag
        Swag.assert(shiftLeft8(value8, first8, second8, flag8) == (flag8 != 0 ? value8 << first8 : value8 << second8))

        let value16 = cast #wrap (u16) value
        let first16 = cast #wrap (u16) first & 15
        let second16 = cast #wrap (u16) second & 15
        let flag16 = cast #wrap (u16) flag
        Swag.assert(shiftRight16(value16, first16, second16, flag16) == (flag16 != 0 ? value16 >> first16 : value16 >> second16))
    }
}
