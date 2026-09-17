#global private

#[Swag.NoInline]
func absDiff64(values: const [*]u64, index: u64) -> u64 => values[index] > values[index + 1] ? values[index] - values[index + 1] : values[index + 1] - values[index]

#[Swag.NoInline]
func absDiff32(values: const [*]u32, index: u64) -> u32 => values[index] > values[index + 1] ? values[index] - values[index + 1] : values[index + 1] - values[index]

#test
{
    let values64 = [0'u64, 1, 1, 0xFFFFFFFFFFFFFFFF, 7]
    Swag.assert(absDiff64(&values64[0], 0) == 1)
    Swag.assert(absDiff64(&values64[0], 1) == 0)
    Swag.assert(absDiff64(&values64[0], 2) == 0xFFFFFFFFFFFFFFFE)
    Swag.assert(absDiff64(&values64[0], 3) == 0xFFFFFFFFFFFFFFF8)

    let values32 = [0'u32, 1, 1, 0xFFFFFFFF, 7]
    Swag.assert(absDiff32(&values32[0], 0) == 1)
    Swag.assert(absDiff32(&values32[0], 1) == 0)
    Swag.assert(absDiff32(&values32[0], 2) == 0xFFFFFFFE)
    Swag.assert(absDiff32(&values32[0], 3) == 0xFFFFFFF8)
}
