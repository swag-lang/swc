#global private

// A loop that loads the element its previous trip stored keeps that value in
// a register: `row[y]` after `row[y + 1] = v` is the edit-distance recurrence.
// Every optimized function is compared with the same code built without
// optimization, on zero, one and many trips, and with a second pointer that
// aliases the row one element ahead, so a store through it overwrites the
// element the next trip loads: that loop must keep reading memory.

#[Swag.Optimize(true), Swag.NoInline]
func prefixRow(row: [*] u64, costs: const [*] u64, n: u64)->u64
{
    for y in n
    {
        let v = row[y] + costs[y]
        row[y + 1] = v ^ (y & 3)
    }
    return row[n]
}

#[Swag.Optimize(false), Swag.NoInline]
func prefixRowRef(row: [*] u64, costs: const [*] u64, n: u64)->u64
{
    for y in n
    {
        let v = row[y] + costs[y]
        row[y + 1] = v ^ (y & 3)
    }
    return row[n]
}

// Two rows of one local frame: the store to the other row is provably apart.
#[Swag.Optimize(true), Swag.NoInline]
func twoLocalRows(seed: u64, n: u64)->u64
{
    var row0, row1: [16] u64
    row1[0] = seed
    for y in n
    {
        let v = row1[y] * 3 + y
        row0[y + 1] = v ^ seed
        row1[y + 1] = v % 1000
    }
    return row1[n] + row0[n]
}

#[Swag.Optimize(false), Swag.NoInline]
func twoLocalRowsRef(seed: u64, n: u64)->u64
{
    var row0, row1: [16] u64
    row1[0] = seed
    for y in n
    {
        let v = row1[y] * 3 + y
        row0[y + 1] = v ^ seed
        row1[y + 1] = v % 1000
    }
    return row1[n] + row0[n]
}

// `other` may point anywhere in `row`: its store may overwrite what the
// next trip loads.
#[Swag.Optimize(true), Swag.NoInline]
func aliasedStore(row, other: [*] u64, n: u64)->u64
{
    for y in n
    {
        let v = row[y] + 2
        row[y + 1] = v
        other[y]   = v * 10
    }
    return row[n]
}

#[Swag.Optimize(false), Swag.NoInline]
func aliasedStoreRef(row, other: [*] u64, n: u64)->u64
{
    for y in n
    {
        let v = row[y] + 2
        row[y + 1] = v
        other[y]   = v * 10
    }
    return row[n]
}

#test
{
    var costs: [12] u64 = [1, 7, 2, 9, 3, 3, 8, 1, 0, 6, 2, 4]
    for n in 12
    {
        var a, b: [13] u64
        a[0] = 4
        b[0] = 4
        Swag.assert(prefixRow(&a[0], &costs[0], n) == prefixRowRef(&b[0], &costs[0], n))
        for i in 13 do
            Swag.assert(a[i] == b[i])
    }

    for n in 15 do
        Swag.assert(twoLocalRows(cast(u64, n) * 77 + 5, n) == twoLocalRowsRef(cast(u64, n) * 77 + 5, n))
}

#test
{
    for n in 9
    {
        var a, b: [12] u64
        a[0] = 1
        b[0] = 1
        // `other` one element ahead of `row`: other[y] is row[y + 1].
        Swag.assert(aliasedStore(&a[0], &a[1], n) == aliasedStoreRef(&b[0], &b[1], n))
        for i in 12 do
            Swag.assert(a[i] == b[i])
        // Disjoint buffers.
        var c, d, e, f: [12] u64
        c[0] = 3
        e[0] = 3
        Swag.assert(aliasedStore(&c[0], &d[0], n) == aliasedStoreRef(&e[0], &f[0], n))
    }
}

// A read window uses the preceding trip's second element, including a
// descending index and a pointer store that may invalidate that element.
#[Swag.Optimize(true), Swag.NoInline]
func window(row: const [*] u64, n: u64)->u64
{
    var sum = 0'u64
    for i in n do sum += row[i] ^ row[i + 1]
    return sum
}

#[Swag.Optimize(false), Swag.NoInline]
func windowRef(row: const [*] u64, n: u64)->u64
{
    var sum = 0'u64
    for i in n do sum += row[i] ^ row[i + 1]
    return sum
}

#[Swag.Optimize(true), Swag.NoInline]
func reverseWindow(row: const [*] u64, n: u64)->u64
{
    var sum = 0'u64
    var i   = n
    while i > 0
    {
        sum += row[i] ^ row[i - 1]
        i   -= 1
    }
    return sum
}

#[Swag.Optimize(false), Swag.NoInline]
func reverseWindowRef(row: const [*] u64, n: u64)->u64
{
    var sum = 0'u64
    var i   = n
    while i > 0
    {
        sum += row[i] ^ row[i - 1]
        i   -= 1
    }
    return sum
}

#[Swag.Optimize(true), Swag.NoInline]
func modifiedWindow(row, other: [*] u64, n: u64)->u64
{
    var sum = 0'u64
    for i in n
    {
        sum      += row[i] ^ row[i + 1]
        other[i] = i * 17
    }
    return sum
}

#[Swag.Optimize(false), Swag.NoInline]
func modifiedWindowRef(row, other: [*] u64, n: u64)->u64
{
    var sum = 0'u64
    for i in n
    {
        sum      += row[i] ^ row[i + 1]
        other[i] = i * 17
    }
    return sum
}

#[Swag.Optimize(true), Swag.NoInline]
func multipleWindows(row: const [*] u64, n: u64)->u64
{
    var sum = 0'u64
    for i in n do sum += row[i] + row[i + 1] * 2 + row[i + 2] * 3
    for i in n do sum += row[i] ^ row[i + 1]
    return sum
}

#[Swag.Optimize(false), Swag.NoInline]
func multipleWindowsRef(row: const [*] u64, n: u64)->u64
{
    var sum = 0'u64
    for i in n do sum += row[i] + row[i + 1] * 2 + row[i + 2] * 3
    for i in n do sum += row[i] ^ row[i + 1]
    return sum
}

#test
{
    for n in 12'u64
    {
        var a, b: [14] u64
        for i in 14
        {
            a[i] = cast(u64, i) * 111
            b[i] = a[i]
        }
        Swag.assert(multipleWindows(&a[0], n) == multipleWindowsRef(&b[0], n))
        Swag.assert(window(&a[0], n) == windowRef(&b[0], n))
        Swag.assert(reverseWindow(&a[0], n) == reverseWindowRef(&b[0], n))
        Swag.assert(modifiedWindow(&a[0], &a[1], n) == modifiedWindowRef(&b[0], &b[1], n))
        for i in 13 do Swag.assert(a[i] == b[i])
    }
}
