#global private

// An `and` inside `(a and b) or c` leaves straight past the join's test when
// its rhs does not hold. Links that multiply, rotate or call, both results,
// and joins whose links stay branchless must keep their truth tables.

#[Swag.Optimize(true), Swag.NoInline]
func isLeap(y: u32)->bool => (y % 4 == 0 and y % 100 != 0) or y % 400 == 0
#[Swag.Optimize(true), Swag.NoInline, Swag.Safety(.Overflow, false)]
func mixed(x, y: u32)->bool => (x * 3 > y and y % 7 != 0) or x * y == 42
#[Swag.Optimize(true), Swag.NoInline]
func identChar(c: u8)->bool => (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '_'
#[Swag.Optimize(true), Swag.NoInline, Swag.Safety(.Overflow, false)]
func threeLinks(x: u32)->u32
{
    if (x % 3 == 0 and x % 5 != 0) or (x * x > 1000 and x % 2 == 0) or x == 1 do
        return 1
    return 0
}

#[Swag.Optimize(false), Swag.NoInline]
func slowLeap(y: u32)->bool
{
    if y % 400 == 0 do return true
    if y % 100 == 0 do return false
    return y % 4 == 0
}
#[Swag.Optimize(false), Swag.NoInline, Swag.Safety(.Overflow, false)]
func slowMixed(x, y: u32)->bool
{
    if x * y == 42 do return true
    if x * 3 <= y do return false
    return y % 7 != 0
}
#[Swag.Optimize(false), Swag.NoInline]
func slowIdent(c: u8)->bool
{
    if c == '_' do return true
    if c >= 'a' and c <= 'z' do return true
    return c >= '0' and c <= '9'
}
#[Swag.Optimize(false), Swag.NoInline, Swag.Safety(.Overflow, false)]
func slowThree(x: u32)->u32
{
    if x == 1 do return 1
    if x % 3 == 0 and x % 5 != 0 do return 1
    if x * x > 1000 and x % 2 == 0 do return 1
    return 0
}

#test
{
    for y in 0'u32 until 2500
    {
        Swag.assert(isLeap(y) == slowLeap(y))
        Swag.assert(threeLinks(y) == slowThree(y))
    }
    for x in 0'u32 until 60
    {
        for y in 0'u32 until 60 do
            Swag.assert(mixed(x, y) == slowMixed(x, y))
    }
    for i in 0 until 256
    {
        let c = cast(u8) i
        Swag.assert(identChar(c) == slowIdent(c))
    }
}
