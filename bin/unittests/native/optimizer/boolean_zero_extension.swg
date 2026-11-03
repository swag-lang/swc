#global private

#[Swag.NoInline]
func unsignedCompare(a, b: u64)->u64 => cast(u64, (a < b))

#[Swag.NoInline]
func signedCompare(a, b: s64)->u32 => cast(u32, (a >= b))

#[Swag.NoInline]
func liveInputs(a, b: u64)->u64 => a ^ b ^ cast(u64, (a == b))

#[Swag.NoInline]
func computedInput(a, b: u64)->u64 => cast(u64, ((a ^ b) != b))

#test
{
    let values = [0'u64, 1, 0x100000000, 0x7FFFFFFFFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        for b in values
        {
            Swag.require(unsignedCompare(a, b) == (a < b ? 1 : 0))
            Swag.require(liveInputs(a, b) == (a ^ b ^ (a == b ? 1 : 0)))
            Swag.require(computedInput(a, b) == (a != 0 ? 1 : 0))
        }
    }
    Swag.require(signedCompare(-1, 1) == 0)
    Swag.require(signedCompare(1, -1) == 1)
    Swag.require(signedCompare(0, 0) == 1)
    Swag.require(signedCompare(-0x7FFFFFFFFFFFFFFF - 1, 0x7FFFFFFFFFFFFFFF) == 0)
}
