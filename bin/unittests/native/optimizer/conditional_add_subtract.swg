#global private
#global #[Swag.Safety(.Overflow, false)]

#[Swag.NoInline]
func addOrSubtract32(a, b, flag: u32)->u32 => flag & 1 != 0 ? a + b : a - b

#[Swag.NoInline]
func addOrSubtract64(a, b, flag: u64)->u64 => flag & 1 != 0 ? a + b : a - b

#test
{
    let values = [0'u64, 1, 7, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values do for b in values do for flag in values
    {
        Swag.assert(addOrSubtract64(a, b, flag) == (flag & 1 != 0 ? a + b : a - b))
        let a32 = cast(u32) a
        let b32 = cast(u32) b
        let flag32 = cast(u32) flag
        Swag.assert(addOrSubtract32(a32, b32, flag32) == (flag32 & 1 != 0 ? a32 + b32 : a32 - b32))
    }
}
