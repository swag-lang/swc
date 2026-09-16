#global private
#global #[Swag.Safety(.Overflow, false)]
using Swag

// ~(x - 1) is -x at both widths, including zero and the most negative value,
// and stays a complement when the decrement has another reader.

#[Swag.Optimize(true), Swag.NoInline]
func alignUp(x, a: u64)->u64 => (x + a - 1) & ~(a - 1)

#[Swag.Optimize(true), Swag.NoInline]
func negated32(x: u32)->u32 => ~(x - 1)

#[Swag.Optimize(true), Swag.NoInline]
func negated64(x: s64)->s64 => ~(x - 1)

#[Swag.Optimize(true), Swag.NoInline]
func keptDecrement(x: u32)->u64
{
    let d = x - 1
    return cast(u64) ~d + cast(u64) d
}

#test
{
    Swag.assert(alignUp(13, 8) == 16)
    Swag.assert(alignUp(16, 8) == 16)
    Swag.assert(alignUp(0, 4096) == 0)
    Swag.assert(negated32(0) == 0)
    Swag.assert(negated32(1) == 0xFFFFFFFF)
    Swag.assert(negated32(0x80000000) == 0x80000000)
    Swag.assert(negated64(5) == -5)
    Swag.assert(negated64(-9223372036854775807 - 1) == -9223372036854775807 - 1)
    Swag.assert(keptDecrement(10) == 0xFFFFFFFF)
}
