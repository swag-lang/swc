#global private

#[Swag.NoInline]
func clampUnsigned32(values: const [*]u32, index: u64) -> u32 => values[index] > 100 ? 100 : values[index]

#[Swag.NoInline]
func clampSigned64(values: const [*]s64, index: u64) -> s64 => values[index] < -100 ? -100 : values[index]

// This limit cannot use x64's sign-extended 32-bit immediate. It protects the
// register form while the small limits above exercise the immediate fold.
#[Swag.NoInline]
func clampWideUnsigned64(values: const [*]u64, index: u64) -> u64 => values[index] > 0x8000000000000000 ? 0x8000000000000000 : values[index]

#test
{
    let unsigned = [0'u32, 99, 100, 101, 0xFFFFFFFF]
    Swag.assert(clampUnsigned32(&unsigned[0], 0) == 0)
    Swag.assert(clampUnsigned32(&unsigned[0], 1) == 99)
    Swag.assert(clampUnsigned32(&unsigned[0], 2) == 100)
    Swag.assert(clampUnsigned32(&unsigned[0], 3) == 100)
    Swag.assert(clampUnsigned32(&unsigned[0], 4) == 100)

    let signed = [-101's64, -100, -99, 0, 9223372036854775807]
    Swag.assert(clampSigned64(&signed[0], 0) == -100)
    Swag.assert(clampSigned64(&signed[0], 1) == -100)
    Swag.assert(clampSigned64(&signed[0], 2) == -99)
    Swag.assert(clampSigned64(&signed[0], 4) == 9223372036854775807)

    let wide = [0'u64, 0x8000000000000000, 0x8000000000000001, 0xFFFFFFFFFFFFFFFF]
    Swag.assert(clampWideUnsigned64(&wide[0], 0) == 0)
    Swag.assert(clampWideUnsigned64(&wide[0], 1) == 0x8000000000000000)
    Swag.assert(clampWideUnsigned64(&wide[0], 2) == 0x8000000000000000)
    Swag.assert(clampWideUnsigned64(&wide[0], 3) == 0x8000000000000000)
}
