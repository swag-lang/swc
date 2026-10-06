#global private

struct Table
{
    prefix: [19] u64
    bytes: [32] u8
    words: [32] s32
    wide: [32] u64
}

#[Swag.Optimize(true), Swag.NoInline]
func update(table: *Table, index: u32, value: u64)->u64
{
    let previous = table.wide[index]
    table.bytes[index] = cast #bit (u8) value
    table.words[index] = cast(s32) value
    table.wide[index] = value + previous
    return table.wide[index] + table.bytes[index] + cast(u64) table.words[index]
}

#[Swag.Optimize(true), Swag.NoInline]
func localArray(index: u32)->u64
{
    var table: Table
    for i in 32 do table.wide[i] = cast(u64) i * 7
    return table.wide[index] + table.wide[(index + 1) & 31]
}

// Both addresses must retain the original source even when the variable that
// held it is redirected before either indexed access.
#[Swag.Optimize(true), Swag.NoInline]
func redirected(first, second: *Table, index: u32)->u64
{
    var table = first
    let saved = cast([*] u64) &table.wide[0]
    table = second
    return saved[index] + table.wide[index]
}

#[Swag.Optimize(true), Swag.NoInline]
func acrossJoin(first, second: *Table, index: u32, redirect: bool)->u64
{
    var selected = first
    let saved = &selected.wide[0]
    if redirect do selected = second
    saved[] += selected.wide[index]
    return first.wide[0]
}

#test
{
    var table: Table
    for i in 32
    {
        let value = cast(u64) i * 13
        table.wide[i] = 100 + i
        Swag.assert(update(&table, i, value) == 100 + i + value * 2 + cast #bit (u8) value)
        Swag.assert(table.bytes[i] == cast #bit (u8) value)
        Swag.assert(table.words[i] == cast(s32) value)
        Swag.assert(table.wide[i] == 100 + i + value)
        Swag.assert(localArray(i) == cast(u64) (i + ((i + 1) & 31)) * 7)
    }
    var other: Table
    for i in 32
    {
        other.wide[i] = i * 2
        Swag.assert(redirected(&table, &other, i) == table.wide[i] + i * 2)
        let before = table.wide[0]
        let increment = table.wide[i]
        Swag.assert(acrossJoin(&table, &other, i, false) == before + increment)
        Swag.assert(acrossJoin(&table, &other, i, true) == before + increment + other.wide[i])
    }
}
