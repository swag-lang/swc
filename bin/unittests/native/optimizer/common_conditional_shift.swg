#global private

#[Swag.NoInline]
func left32(value, first, second, flag: u32)->u32 => flag != 0 ? value << first : value << second
#[Swag.NoInline]
func right32(value, first, second, flag: u32)->u32 => flag != 0 ? value >> first : value >> second
#[Swag.NoInline]
func left64(value, first, second, flag: u64)->u64 => flag != 0 ? value << first : value << second
#[Swag.NoInline]
func right64(value, first, second, flag: u64)->u64 => flag != 0 ? value >> first : value >> second

#test
{
    // Shift counts stay below the width they shift: anywhere else a shift is
    // a runtime error under safety and unspecified without it.
    let values = [0'u64, 1, 7, 31, 32, 63, 64, 0xFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for value in values do for first in values do for second in values do for flag in values
                {
                    let count    = first & 63
                    let other    = second & 63
                    let selected = flag != 0 ? count : other
                    Swag.assert(left64(value, count, other, flag) == value << selected)
                    Swag.assert(right64(value, count, other, flag) == value >> selected)

                    let value32    = cast #wrap (u32) value
                    let count32    = cast #wrap (u32) first & 31
                    let other32    = cast #wrap (u32) second & 31
                    let flag32     = cast #wrap (u32) flag
                    let selected32 = flag32 != 0 ? count32 : other32
                    Swag.assert(left32(value32, count32, other32, flag32) == value32 << selected32)
                    Swag.assert(right32(value32, count32, other32, flag32) == value32 >> selected32)
                }
}
