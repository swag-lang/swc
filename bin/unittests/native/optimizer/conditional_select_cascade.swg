#global private

#[Swag.NoInline]
func clamp(values: const [*]u64, index: u64, low: u64, high: u64)->u64 => Swag.min(Swag.max(values[index], low), high)

#[Swag.NoInline]
func clamp32(values: const [*]u32, index: u64, low: u32, high: u32)->u32 => Swag.min(Swag.max(values[index], low), high)

#test
{
    let values = [0'u64, 4, 5, 7, 8, 0xFFFFFFFFFFFFFFFF]
    let results = [5'u64, 5, 5, 7, 7, 7]
    for value, index in values do
        Swag.assert(clamp(&values[0], index, 5, 7) == results[index])

    let values32 = [0'u32, 4, 5, 7, 8, 0xFFFFFFFF]
    for value, index in values32 do
        Swag.assert(clamp32(&values32[0], index, 5, 7) == results[index])
}
