#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func complemented(a, b: u64)->u64 => ~(~a + b)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func swapped(a, b: u64)->u64 => ~(b + ~a)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func complemented32(a, b: u32)->u32 => ~(~a + b)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func constant(a: u64)->u64 => ~(~a + 7)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func negativeConstant(a: u64)->u64 => ~(~a - 7)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func shared(a, b: u64)->u64
{
    let inverse = ~a
    return ~(inverse + b) ^ inverse
}
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func compared(a, b: u64)->bool => ~(~a + b) == 0
#[Swag.NoInline, Swag.Safety(.Overflow, true)]
func checked(a, b: u64)->u64 => ~(~a + b)

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 7, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xAAAAAAAAAAAAAAAA, 0x5555555555555555, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        Swag.assert(constant(a) == a - 7)
        Swag.assert(negativeConstant(a) == a + 7)
        for b in values
        {
            Swag.assert(complemented(a, b) == a - b)
            Swag.assert(swapped(a, b) == a - b)
            Swag.assert(shared(a, b) == ((a - b) ^ ~a))
            Swag.assert(compared(a, b) == (a == b))
            let lowA = cast(u32) (a & 0xFFFFFFFF)
            let lowB = cast(u32) (b & 0xFFFFFFFF)
            Swag.assert(complemented32(lowA, lowB) == lowA - lowB)
        }
    }
    Swag.assert(checked(9, 3) == 6)
}
