#global private

#[Swag.NoInline]
func clearLowest64(values: [*] u64, index: u64)->u64 => values[index] & (values[index] - 1)

#[Swag.NoInline]
func clearLowest32(values: [*] u32, index: u64)->u32 => values[index] & (values[index] - 1)

#test
{
    var values64: [5] u64 = [0, 1, 2, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    Swag.assert(clearLowest64(&values64[0], 0) == 0)
    Swag.assert(clearLowest64(&values64[0], 1) == 0)
    Swag.assert(clearLowest64(&values64[0], 2) == 0)
    Swag.assert(clearLowest64(&values64[0], 3) == 0)
    Swag.assert(clearLowest64(&values64[0], 4) == 0xFFFFFFFFFFFFFFFE)

    var values32: [5] u32 = [0, 1, 2, 0x80000000, 0xFFFFFFFF]
    Swag.assert(clearLowest32(&values32[0], 0) == 0)
    Swag.assert(clearLowest32(&values32[0], 1) == 0)
    Swag.assert(clearLowest32(&values32[0], 2) == 0)
    Swag.assert(clearLowest32(&values32[0], 3) == 0)
    Swag.assert(clearLowest32(&values32[0], 4) == 0xFFFFFFFE)
}
