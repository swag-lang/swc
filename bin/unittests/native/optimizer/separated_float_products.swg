#global private

// A product accumulated into a value loaded right before the accumulation: the load sits
// between the multiply and the add or subtract, and the pair may still contract. Every
// operand is a small integer, so the fused and the separate roundings agree exactly.

struct Velocity
{
    vx, vy, vz: f64
}

#[Swag.Optimize(true), Swag.NoInline]
func push(v: *Velocity, dx, dy, dz, scale: f64)
{
    v.vx -= dx * scale
    v.vy += dy * scale
    v.vz -= dz * scale
}

// The product stays live after the accumulation: it must not be folded away.
#[Swag.Optimize(true), Swag.NoInline]
func pushAndKeep(v: *Velocity, dx, scale: f64)->f64
{
    let product = dx * scale
    v.vx += product
    return product + v.vy
}

// A factor is overwritten between the product and the accumulation.
#[Swag.Optimize(true), Swag.NoInline]
func pushAfterRescale(v: *Velocity, dx: f64, scale: *f64)->f64
{
    var s       = scale[]
    let product = dx * s
    s           = v.vz
    v.vx += product
    return s
}

#test
{
    var v = Velocity{10.0, 20.0, 30.0}
    push(&v, 1.0, 2.0, 3.0, 4.0)
    Swag.assert(v.vx == 6.0)
    Swag.assert(v.vy == 28.0)
    Swag.assert(v.vz == 18.0)

    Swag.assert(pushAndKeep(&v, 2.0, 5.0) == 38.0)
    Swag.assert(v.vx == 16.0)

    var scale = 3.0'f64
    Swag.assert(pushAfterRescale(&v, 2.0, &scale) == 18.0)
    Swag.assert(v.vx == 22.0)
}
