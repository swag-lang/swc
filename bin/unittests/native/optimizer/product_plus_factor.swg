#global private
#global #[Swag.Safety(.Overflow, false)]

#[Swag.NoInline]
func add(a, b: u64)->u64 => a * b + a
#[Swag.NoInline]
func reversed(a, b: u64)->u64 => a + a * b
#[Swag.NoInline]
func subtract(a, b: u64)->u64 => a * b - a
#[Swag.NoInline]
func right(a, b: u64)->u64 => a * b + b
#[Swag.NoInline]
func narrow(a, b: u32)->u32 => a * b + a
#[Swag.NoInline]
func sharedFactor(a, b: u64)->u64 => (a * b + a) ^ b
#[Swag.NoInline]
func sharedProduct(a, b: u64)->u64
{
    let product = a * b
    return (product + a) ^ product
}
#[Swag.NoInline]
func changed(a, b: u64)->u64
{
    var current = a
    let product = current * b
    current += 7
    return product + current
}
#[Swag.NoInline, Swag.Safety(.Overflow, true)]
func checked(a, b: u64)->u64 => a * b + a

#test
{
    let values = [0'u64, 1, 2, 7, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        for b in values
        {
            let product = a * b
            Swag.require(add(a, b) == product + a)
            Swag.require(reversed(a, b) == product + a)
            Swag.require(subtract(a, b) == product - a)
            Swag.require(right(a, b) == product + b)
            let lowA = cast(u32, (a & 0xFFFFFFFF))
            let lowB = cast(u32, (b & 0xFFFFFFFF))
            Swag.require(narrow(lowA, lowB) == lowA * lowB + lowA)
            Swag.require(sharedFactor(a, b) == ((product + a) ^ b))
            Swag.require(sharedProduct(a, b) == ((product + a) ^ product))
            Swag.require(changed(a, b) == product + (a + 7))
        }
    }
    Swag.require(checked(7, 9) == 70)
    Swag.require(checked(0xFFFFFFFFFFFFFFFF, 0) == 0xFFFFFFFFFFFFFFFF)
}
