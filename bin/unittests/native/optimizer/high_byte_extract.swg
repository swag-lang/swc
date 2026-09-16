#global private

#[Swag.NoInline]
func first(a: u64)->u64 => (a >> 8) & 255
#[Swag.NoInline]
func second(a, b: u64)->u64 => ((b >> 8) & 255) ^ a
#[Swag.NoInline]
func third(a, b, c, d: u64)->u64 => ((c >> 8) & 255) ^ a ^ b ^ d
#[Swag.NoInline]
func fourth(a, b, c, d: u64)->u64 => ((d >> 8) & 255) ^ a ^ b ^ c
#[Swag.NoInline]
func signedByte(a: s64)->u64 => cast(u64) ((a >> 8) & 255)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func product(a, b: u64)->u64 => ((a * b) >> 8) & 255
#[Swag.NoInline]
func shared(a: u64)->u64
{
    let shifted = a >> 8
    return shifted ^ (shifted & 255)
}
#[Swag.NoInline]
func variable(a, count: u64)->u64 => (a >> count) & 255

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 0x100, 0x1234, 0xABCD, 0x123456789ABCDEF0, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        Swag.assert(first(a) == variable(a, 8))
        Swag.assert(signedByte(cast #bit (s64) a) == variable(a, 8))
        Swag.assert(shared(a) == ((a >> 8) & 0xFFFFFFFFFFFFFF00))
        for b in values
        {
            Swag.assert(second(a, b) == (variable(b, 8) ^ a))
            Swag.assert(third(a, b, ~a, ~b) == (variable(~a, 8) ^ a ^ b ^ ~b))
            Swag.assert(fourth(a, b, ~a, ~b) == (variable(~b, 8) ^ a ^ b ^ ~a))
            Swag.assert(product(a, b) == variable(a * b, 8))
        }
    }
}
