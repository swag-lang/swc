#global private

#[Swag.NoInline]
func minimum(values: const [*]u64, index: u64)->u64 => Swag.min(Swag.min(values[index], values[index + 1]), Swag.min(values[index + 2], values[index + 3]))

#[Swag.NoInline]
func maximum(values: const [*]u64, index: u64)->u64 => Swag.max(Swag.max(values[index], values[index + 1]), Swag.max(values[index + 2], values[index + 3]))

#test
{
    let values = [9'u64, 3, 7, 5, 0xFFFFFFFFFFFFFFFF, 12, 42, 1]
    Swag.assert(minimum(&values[0], 0) == 3)
    Swag.assert(maximum(&values[0], 0) == 9)
    Swag.assert(minimum(&values[0], 4) == 1)
    Swag.assert(maximum(&values[0], 4) == 0xFFFFFFFFFFFFFFFF)
}
