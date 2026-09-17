#global private

#[Swag.NoInline]
func mask7(value: u64)->u64 => value & 7

#[Swag.NoInline]
func maskSignedDword(value: u64)->u64 => value & 0x7FFFFFFF

#[Swag.NoInline]
func keepBit31(value: u64)->u64 => value & 0x80000000

#test
{
    for value in [0'u64, 1, 7, 8, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFFFFFFFFFF]
    {
        Swag.assert(mask7(value) == (value & 7))
        Swag.assert(maskSignedDword(value) == (value & 0x7FFFFFFF))
        Swag.assert(keepBit31(value) == (value & 0x80000000))
    }
}
