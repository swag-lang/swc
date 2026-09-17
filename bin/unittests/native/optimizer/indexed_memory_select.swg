#global private

#[Swag.NoInline]
func zeroFallback64(values: [*] u64, index, fallback: u64)->u64 => values[index] == 0 ? fallback : values[index]

#[Swag.NoInline]
func nonzeroFallback32(values: [*] u32, index: u64, fallback: u32)->u32 => values[index] != 0 ? fallback : values[index]

#test
{
    var values64: [4] u64 = [0, 1, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    Swag.assert(zeroFallback64(&values64[0], 0, 17) == 17)
    Swag.assert(zeroFallback64(&values64[0], 1, 17) == 1)
    Swag.assert(zeroFallback64(&values64[0], 2, 17) == 0x8000000000000000)

    var values32: [4] u32 = [0, 1, 0x80000000, 0xFFFFFFFF]
    Swag.assert(nonzeroFallback32(&values32[0], 0, 23) == 0)
    Swag.assert(nonzeroFallback32(&values32[0], 1, 23) == 23)
    Swag.assert(nonzeroFallback32(&values32[0], 3, 23) == 23)
}
