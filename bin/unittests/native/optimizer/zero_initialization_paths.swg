#global private
#global #[Swag.Safety(.Overflow, false)]

#[Swag.NoInline]
func sum(p: [*]u64, count: u64)->u64
{
    var result = 0'u64
    for i in 0 until count do result += p[i]
    return result
}
#[Swag.NoInline]
func countNonzero(p: [*]u64, count: u64)->u64
{
    var result = 0'u64
    for i in 0 until count
    {
        if p[i] != 0 do result += 1
    }
    return result
}
#[Swag.NoInline]
func nested(p: [*]u64, count: u64, gate: bool)->u64
{
    var result = 0'u64
    if gate
    {
        for i in 0 until count
        {
            if p[i] == 0 do break
            result += p[i]
        }
    }
    return result
}
#[Swag.NoInline]
func selected(a, b: u64)->u64 => a < b ? a : 0

#test
{
    var values = [1'u64, 2, 0, 4, 0xFFFFFFFFFFFFFFFF]
    Swag.assert(sum(&values[0], 0) == 0)
    Swag.assert(sum(&values[0], 5) == 6)
    Swag.assert(countNonzero(&values[0], 0) == 0)
    Swag.assert(countNonzero(&values[0], 5) == 4)
    Swag.assert(nested(&values[0], 5, false) == 0)
    Swag.assert(nested(&values[0], 5, true) == 3)
    Swag.assert(selected(3, 7) == 3)
    Swag.assert(selected(7, 3) == 0)
    Swag.assert(selected(0xFFFFFFFFFFFFFFFF, 3) == 0)
}
