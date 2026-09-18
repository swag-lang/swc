#global private

// A field of a wide array element - sixteen or thirty-two bytes, wider than
// any address scale - is read through the element index shifted into place.
// Sums, plain loads and float fields must match the unfolded accesses.

struct Pair
{
    id:    u32
    w:     s32
    price: s64
}

struct Wide
{
    a, b: s64
    x, y: f64
}

#[Swag.Optimize(true), Swag.NoInline]
func sumPrices(p: const [*] Pair, n: u64)->s64
{
    var t = 0's64
    for i in n do t += p[i].price
    return t
}
#[Swag.Optimize(false), Swag.NoInline]
func sumPricesRef(p: const [*] Pair, n: u64)->s64
{
    var t = 0's64
    for i in n do t += p[i].price
    return t
}

#[Swag.Optimize(true), Swag.NoInline]
func weightAt(p: const [*] Pair, i: u64)->s32 => p[i].w
#[Swag.Optimize(true), Swag.NoInline]
func yAt(p: const [*] Wide, i: u64)->f64 => p[i].y

#[Swag.Optimize(true), Swag.NoInline]
func sumX(p: const [*] Wide, n: u64)->f64
{
    var t = 0.0'f64
    for i in n do t += p[i].x
    return t
}
#[Swag.Optimize(false), Swag.NoInline]
func sumXRef(p: const [*] Wide, n: u64)->f64
{
    var t = 0.0'f64
    for i in n do t += p[i].x
    return t
}

#test
{
    let pairs: [4] Pair = [{1, -2, 30}, {2, 5, -12}, {3, 7, 100}, {4, -9, 5}]
    Swag.assert(sumPrices(&pairs[0], 4) == sumPricesRef(&pairs[0], 4))
    for i in 4 do
        Swag.assert(weightAt(&pairs[0], i) == pairs[i].w)

    let wides: [3] Wide = [{1, 2, 0.5, -1.5}, {3, 4, 2.25, 8}, {5, 6, -4, 0.125}]
    Swag.assert(sumX(&wides[0], 3) == sumXRef(&wides[0], 3))
    for i in 3 do
        Swag.assert(yAt(&wides[0], i) == wides[i].y)
}
