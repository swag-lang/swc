#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func add64(value: u64)->u64 => (value << 3) + (value << 1)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func subtract64(value: u64)->u64 => (value << 3) - (value << 1)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func add32(value: u32)->u32 => (value << 3) + (value << 1)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func subtract32(value: u32)->u32 => (value << 3) - (value << 1)

#test
{
    for value in [0'u64, 1, 2, 7, 0x7FFFFFFF, 0xFFFFFFFF, 0xFFFFFFFFFFFFFFFF]
    {
        Swag.assert(add64(value) == value * #wrap 10)
        Swag.assert(subtract64(value) == value * #wrap 6)
        let value32 = cast #wrap (u32) value
        Swag.assert(add32(value32) == value32 * #wrap 10)
        Swag.assert(subtract32(value32) == value32 * #wrap 6)
    }
}
