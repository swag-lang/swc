#global private

// Remainders by a constant compared with zero become divisibility tests: a
// multiply by the divisor's inverse, a rotation and a bound. Odd and even
// divisors, 32 and 64 bits, and both senses of the test must agree with a
// division by the same value held in a variable.

#[Swag.Optimize(true), Swag.NoInline]
func by3(x: u32)->bool => x % 3 == 0
#[Swag.Optimize(true), Swag.NoInline]
func by10(x: u32)->bool => x % 10 == 0
#[Swag.Optimize(true), Swag.NoInline]
func notBy100(x: u32)->bool => x % 100 != 0
#[Swag.Optimize(true), Swag.NoInline]
func by400(x: u32)->bool => x % 400 == 0
#[Swag.Optimize(true), Swag.NoInline]
func by7Wide(x: u64)->bool => x % 7 == 0
#[Swag.Optimize(true), Swag.NoInline]
func notBy1000000Wide(x: u64)->bool => x % 1000000 != 0
#[Swag.Optimize(true), Swag.NoInline]
func isLeap(y: u32)->bool => (y % 4 == 0 and y % 100 != 0) or y % 400 == 0
#[Swag.Optimize(true), Swag.NoInline]
func countBy6(first, last: u32)->u32
{
    var count = 0'u32
    for x in first until last
    {
        if x % 6 == 0 do
            count += 1
    }
    return count
}

#[Swag.NoInline]
func divides32(x, d: u32)->bool => x % d == 0
#[Swag.NoInline]
func divides64(x, d: u64)->bool => x % d == 0

func check(v: u64)
{
    let x32 = cast #wrap (u32) v
    Swag.assert(by3(x32) == divides32(x32, 3))
    Swag.assert(by10(x32) == divides32(x32, 10))
    Swag.assert(notBy100(x32) == not divides32(x32, 100))
    Swag.assert(by400(x32) == divides32(x32, 400))
    Swag.assert(isLeap(x32) == ((divides32(x32, 4) and not divides32(x32, 100)) or divides32(x32, 400)))
    Swag.assert(by7Wide(v) == divides64(v, 7))
    Swag.assert(notBy1000000Wide(v) == not divides64(v, 1000000))
}

#test
{
    for v in 0 until 1300 do
        check(cast(u64) v)
    for v in [0xFFFFFFFF'u64, 0xFFFFFFFE, 0xFFFFFFFD, 0xFFFFFF9C, 0x80000000, 4294967200, 4294967000, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFF9, 7000000000000000000, 18446744073709000000] do
        check(v)

    Swag.assert(countBy6(0, 100) == 17)
    Swag.assert(countBy6(1, 7) == 1)
}
