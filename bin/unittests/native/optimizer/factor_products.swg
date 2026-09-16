#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func sum(a, b, c: u64)->u64 => a * b + a * c
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func difference(a, b, c: u64)->u64 => a * b - a * c
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func cancelled(a, b: u64)->u64 => a * (b + 1) - a * b
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func narrow(a, b, c: u32)->u32 => a * b - a * c
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func shared(a, b, c: u64)->u64
{
    let product = a * b
    return (product + a * c) ^ product
}
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func multiply(a, b: u64)->u64 => a * b
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func signedSum(a, b, c: s64)->s64 => a * b + a * c
#[Swag.NoInline]
func safeSum(a, b, c: u64)->u64 => a * b + a * c

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 2, 7, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        for b in values
        {
            Swag.assert(cancelled(a, b) == a)
            for c in values
            {
                let first  = multiply(a, b)
                let second = multiply(a, c)
                Swag.assert(sum(a, b, c) == first + second)
                Swag.assert(difference(a, b, c) == first - second)
                Swag.assert(shared(a, b, c) == ((first + second) ^ first))
                Swag.assert(narrow(cast(u32) (a & 0xFFFFFFFF), cast(u32) (b & 0xFFFFFFFF), cast(u32) (c & 0xFFFFFFFF)) == cast(u32) ((first - second) & 0xFFFFFFFF))
                Swag.assert(cast #bit (u64) signedSum(cast #bit (s64) a, cast #bit (s64) b, cast #bit (s64) c) == first + second)
            }
        }
    }
    Swag.assert(safeSum(3, 7, 11) == 54)
}
