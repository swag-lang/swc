#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func cancelAddedLeft(a, b: u64)->u64 => (a + b) - a

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func cancelAddedRight(a, b: u64)->u64 => (a + b) - b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func cancelSubtracted(a, b: u64)->u64 => (a - b) + b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func cancelSubtractedCommuted(a, b: u64)->u64 => b + (a - b)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func cancel32(a, b: u32)->u32 => (a + b) - a

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func keepSubtractionOrder(a, b: u64)->u64 => a - (a + b)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func keepSubtractionInput(a, b: u64)->u64 => (a - b) + a

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func reusedSum(a, b: u64)->u64
{
    let sum = a + b
    return (sum - a) ^ sum
}

#[Swag.NoInline, Swag.Safety(.Overflow, true)]
func checkedCancellation(a, b: u64)->u64 => (a + b) - a

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 0xFFFFFFFF, 0x100000000, 0xFFFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF, 0x8000000000000000]
    for a in values
    {
        for b in values
        {
            Swag.assert(cancelAddedLeft(a, b) == b)
            Swag.assert(cancelAddedRight(a, b) == a)
            Swag.assert(cancelSubtracted(a, b) == a)
            Swag.assert(cancelSubtractedCommuted(a, b) == a)
            let a32 = cast(u32) (a & 0xFFFFFFFF)
            let b32 = cast(u32) (b & 0xFFFFFFFF)
            Swag.assert(cancel32(a32, b32) == b32)
            Swag.assert(keepSubtractionOrder(a, b) == (~b + 1))
            Swag.assert(keepSubtractionInput(a, b) == ((a * 2) - b))
            Swag.assert(reusedSum(a, b) == (b ^ (a + b)))
        }
    }
    Swag.assert(checkedCancellation(0x8000000000000000, 17) == 17)
}
