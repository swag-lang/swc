#global private

// A test a dominating one already decides goes away: the guard a loop puts
// before its first iteration after `if n == 0 return`, a bound implied by a
// wider one, signed and unsigned. Tests the dominating one leaves open stay.

#[Swag.Optimize(true), Swag.NoInline]
func sumGuarded(p: const [*] u32, n: u64)->u64
{
    if n == 0 do
        return 0
    var s = 0'u64
    for i in n do
        s += p[i]
    return s
}

#[Swag.Optimize(true), Swag.NoInline]
func sumFromTwo(p: const [*] u32, n: u64)->u64
{
    if n < 2 do
        return 0
    var s = 0'u64
    for i in n do
        s += p[i]
    return s
}

#[Swag.Optimize(true), Swag.NoInline]
func signedBands(x: s32)->s32
{
    if x < 10 do
        return -1
    if x > 3 do
        return 1
    return 0
}

#[Swag.Optimize(true), Swag.NoInline]
func openBands(x: u64)->u32
{
    if x < 5 do
        return 0
    if x < 7 do
        return 1
    return 2
}

#[Swag.Optimize(true), Swag.NoInline]
func negativeBands(x: s64)->s32
{
    if x >= 0 do
        return 0
    if x < 0 do
        return 1
    return 2
}

#[Swag.Optimize(true), Swag.NoInline]
func sumBoth(a, b: const *u32?)->u32
{
    if a == null or b == null do
        return 0
    return a[] + b[]
}

#test
{
    let one = 1'u32
    let two = 2'u32
    Swag.assert(sumBoth(&one, &two) == 3)
    Swag.assert(sumBoth(&one, null) == 0)
    Swag.assert(sumBoth(null, &two) == 0)

    let values: [4] u32 = [1, 2, 3, 4]
    Swag.assert(sumGuarded(&values[0], 0) == 0)
    Swag.assert(sumGuarded(&values[0], 1) == 1)
    Swag.assert(sumGuarded(&values[0], 4) == 10)
    Swag.assert(sumFromTwo(&values[0], 1) == 0)
    Swag.assert(sumFromTwo(&values[0], 2) == 3)
    Swag.assert(sumFromTwo(&values[0], 4) == 10)

    Swag.assert(signedBands(-50) == -1)
    Swag.assert(signedBands(9) == -1)
    Swag.assert(signedBands(10) == 1)
    Swag.assert(signedBands(2147483647) == 1)

    Swag.assert(openBands(4) == 0)
    Swag.assert(openBands(5) == 1)
    Swag.assert(openBands(6) == 1)
    Swag.assert(openBands(7) == 2)
    Swag.assert(openBands(0xFFFFFFFFFFFFFFFF) == 2)

    Swag.assert(negativeBands(0) == 0)
    Swag.assert(negativeBands(-1) == 1)
    Swag.assert(negativeBands(-9223372036854775807 - 1) == 1)
}
