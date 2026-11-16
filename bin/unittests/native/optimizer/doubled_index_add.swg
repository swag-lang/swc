#global private

#[Swag.NoInline, Swag.Optimize(true), Swag.Safety(.Overflow, false)]
func mix32(index, addend: u32)->u32 => index * 2 + addend

#[Swag.NoInline, Swag.Optimize(true), Swag.Safety(.Overflow, false)]
func mix64(index, addend: u64)->u64 => index * 2 + addend

#test
{
    Swag.require(mix32(7, 3) == 17)
    Swag.require(mix32(0x80000000, 7) == 7)
    Swag.require(mix32(0xFFFFFFFF, 1) == 0xFFFFFFFF)
    Swag.require(mix64(7, 3) == 17)
    Swag.require(mix64(0x8000000000000000, 7) == 7)
    Swag.require(mix64(0xFFFFFFFFFFFFFFFF, 1) == 0xFFFFFFFFFFFFFFFF)
}
