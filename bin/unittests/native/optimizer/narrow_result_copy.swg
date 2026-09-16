#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func added(a, b: u32)->u64 => cast(u64) (a + b)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func product(a, b: u32)->u64 => cast(u64) (a * b)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func rotated(a, b: u32)->u64 => cast(u64) ((a << 7) | (a >> 25))
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func shifted(a, b: u32)->u64 => cast(u64) (a << 3)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func inverted(a, b: u32)->u64 => cast(u64) (~a)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func square(a, b: u32)->u64 => cast(u64) ((a + b) * (a + b))
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func preserved(a, b: u32)->u64 => cast(u64) ((a + b) ^ a)
#[Swag.NoInline]
func wide(a, b: u64)->u64 => a ^ b

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u32, 1, 7, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF]
    for a in values
    {
        for b in values
        {
            let sum        = a + b
            let multiplied = a * b
            let rotation   = (a << 7) | (a >> 25)
            let shift      = a << 3
            let squared    = sum * sum
            Swag.assert(added(a, b) == sum)
            Swag.assert(product(a, b) == multiplied)
            Swag.assert(rotated(a, b) == rotation)
            Swag.assert(shifted(a, b) == shift)
            Swag.assert(inverted(a, b) == cast(u64) ~a)
            Swag.assert(square(a, b) == squared)
            Swag.assert(preserved(a, b) == (sum ^ a))
            let high = 0x8000000000000000 | cast(u64) a
            Swag.assert(wide(high, b) == (high ^ cast(u64) b))
        }
    }
}
