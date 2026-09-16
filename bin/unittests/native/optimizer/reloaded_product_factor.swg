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
            Swag.assert(add(&cell, factor) == product + value)
            Swag.assert(subtract(&cell, factor) == product - value)
            Swag.assert(reversed(&cell, factor) == product + value)
            Swag.assert(sharedFactor(&cell, factor) == ((product + value) ^ factor))
            Swag.assert(offset(&cells[0], factor) == product + value)
            Swag.assert(sharedProduct(&cell, factor) == ((product + value) ^ product))
            var other = 29'u64
            Swag.assert(distinct(&cell, &other, factor) == product + 29)
            Swag.assert(distinct(&cell, &cell, factor) == product + value)
            Swag.assert(overwrite(&cell, &other, factor) == product + value)
            Swag.assert(other == 17 and cell == value)
            Swag.assert(overwrite(&cell, &cell, factor) == product + 17)
            Swag.assert(cell == 17)
            cell = value
            Swag.assert(callBetween(&cell, factor) == product + (value + 7))
            Swag.assert(cell == value + 7)
        }
    }
    var safe = 7'u64
    Swag.assert(checked(&safe, 9) == 70)
    safe = 0xFFFFFFFFFFFFFFFF
    Swag.assert(checked(&safe, 0) == safe)
}
