#global private

#[Swag.NoInline]
func combine32(a: f32, b: f32, c: f32, d: f32)->f32
{
    return a + b + c + d
}

#[Swag.NoInline]
func combine64(a: f64, b: f64, c: f64, d: f64)->f64
{
    return a + b + c + d
}

// Repeated literals must stay intact across calls and loop backedges.
#[Swag.NoInline]
func literals32(count: s32)->f32
{
    var total = 0.0'f32
    for index in count
    {
        let x = cast(f32) index
        total += combine32(x * 0.5 + 1.25, x * 0.5 - 1.25, x * 0.5 + 0.75, x * 0.5 - 0.75)
    }
    return total
}

#[Swag.NoInline]
func literals64(count: s32)->f64
{
    var total = 0.0'f64
    for index in count
    {
        let x = cast(f64) index
        total += combine64(x * 0.5 + 1.25, x * 0.5 - 1.25, x * 0.5 + 0.75, x * 0.5 - 0.75)
    }
    return total
}

#test
{
    Swag.assert(literals32(0) == 0)
    Swag.assert(literals32(9) == 72)
    Swag.assert(literals64(0) == 0)
    Swag.assert(literals64(9) == 72)
}
