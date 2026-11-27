#global private

#[Swag.NoInline]
func shiftRightSigned(value: s64, first, second: u32, flag: u64)->s64 => flag != 0 ? value >> first : value >> second
#[Swag.NoInline]
func shiftRightSignedWide(value, first, second, flag: s64)->s64 => flag != 0 ? value >> first : value >> second
#[Swag.NoInline]
func shiftLeft(value: u64, first, second: u32, flag: u64)->u64 => flag != 0 ? value << first : value << second

#test
{
    let values = [0_u64, 1, 0x7FFFFFFFFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    let counts = [0_u32, 1, 7, 31, 32, 63]
    for value in values
    {
        for first in counts
        {
            for second in counts
            {
                for flag in [0_u64, 1, 0xFFFFFFFFFFFFFFFF]
                {
                    let signed = cast #wrap (s64, value)
                    Swag.require(shiftRightSigned(signed, first, second, flag) == (flag != 0 ? signed >> first : signed >> second))
                    Swag.require(shiftRightSignedWide(signed, first, second, cast #wrap (s64, flag)) == (flag != 0 ? signed >> first : signed >> second))
                    Swag.require(shiftLeft(value, first, second, flag) == (flag != 0 ? value << first : value << second))
                }
            }
        }
    }
}
