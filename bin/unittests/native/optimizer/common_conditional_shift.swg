#global private

#[Swag.NoInline] func left32(value, first, second, flag: u32)->u32 => flag != 0 ? value << first : value << second
#[Swag.NoInline] func right32(value, first, second, flag: u32)->u32 => flag != 0 ? value >> first : value >> second
#[Swag.NoInline] func left64(value, first, second, flag: u64)->u64 => flag != 0 ? value << first : value << second
#[Swag.NoInline] func right64(value, first, second, flag: u64)->u64 => flag != 0 ? value >> first : value >> second

#test
{
    let values = [0'u64, 1, 7, 31, 32, 63, 64, 0xFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for value in values do for first in values do for second in values do for flag in values
    {
        let selected = flag != 0 ? first : second
        Swag.assert(left64(value, first, second, flag) == value << selected)
        Swag.assert(right64(value, first, second, flag) == value >> selected)

        let value32 = cast(u32) value
        let first32 = cast(u32) first
        let second32 = cast(u32) second
        let flag32 = cast(u32) flag
        let selected32 = flag32 != 0 ? first32 : second32
        Swag.assert(left32(value32, first32, second32, flag32) == value32 << selected32)
        Swag.assert(right32(value32, first32, second32, flag32) == value32 >> selected32)
    }
}
