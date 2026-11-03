#global private
#global #[Swag.Safety(.Overflow, false)]

#[Swag.NoInline]
func add(p: *u64, a: u64)->u64 => p[] * a + p[]
#[Swag.NoInline]
func subtract(p: *u64, a: u64)->u64 => p[] * a - p[]
#[Swag.NoInline]
func reversed(p: *u64, a: u64)->u64 => p[] + p[] * a
#[Swag.NoInline]
func sharedFactor(p: *u64, a: u64)->u64 => (p[] * a + p[]) ^ a
#[Swag.NoInline]
func offset(p: [*]u64, a: u64)->u64 => p[17] * a + p[17]
#[Swag.NoInline]
func distinct(p, q: *u64, a: u64)->u64 => p[] * a + q[]
#[Swag.NoInline]
func sharedProduct(p: *u64, a: u64)->u64
{
    let product = p[] * a
    return (product + p[]) ^ product
}
#[Swag.NoInline]
func overwrite(p, q: *u64, a: u64)->u64
{
    let product = p[] * a
    q[] = 17
    return product + p[]
}
#[Swag.NoInline]
func update(p: *u64) { p[] += 7 }
#[Swag.NoInline]
func callBetween(p: *u64, a: u64)->u64
{
    let product = p[] * a
    update(p)
    return product + p[]
}
#[Swag.NoInline, Swag.Safety(.Overflow, true)]
func checked(p: *u64, a: u64)->u64 => p[] * a + p[]

#test
{
    let values = [0'u64, 1, 7, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    var cells: [18]u64
    for value in values
    {
        for factor in values
        {
            var cell = value
            cells[17] = value
            let product = value * factor
            Swag.require(add(&cell, factor) == product + value)
            Swag.require(subtract(&cell, factor) == product - value)
            Swag.require(reversed(&cell, factor) == product + value)
            Swag.require(sharedFactor(&cell, factor) == ((product + value) ^ factor))
            Swag.require(offset(&cells[0], factor) == product + value)
            Swag.require(sharedProduct(&cell, factor) == ((product + value) ^ product))
            var other = 29'u64
            Swag.require(distinct(&cell, &other, factor) == product + 29)
            Swag.require(distinct(&cell, &cell, factor) == product + value)
            Swag.require(overwrite(&cell, &other, factor) == product + value)
            Swag.require(other == 17 and cell == value)
            Swag.require(overwrite(&cell, &cell, factor) == product + 17)
            Swag.require(cell == 17)
            cell = value
            Swag.require(callBetween(&cell, factor) == product + (value + 7))
            Swag.require(cell == value + 7)
        }
    }
    var safe = 7'u64
    Swag.require(checked(&safe, 9) == 70)
    safe = 0xFFFFFFFFFFFFFFFF
    Swag.require(checked(&safe, 0) == safe)
}
