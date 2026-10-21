#global private
using Swag

struct Particle
{
    x, y, z:    f64
    vx, vy, vz: f64
    mass:       f64
}

// The velocities are written one field at a time, then the positions advance two
// fields at a time: in release, the packed update reads both velocity fields of
// the stores the same trip of the outer loop just made.
#[Swag.Optimize(true), Swag.NoInline]
func stepParticles(particles: [..] Particle, dt: f64, steps: u64)
{
    for steps
    {
        for &p in particles
        {
            p.vx += p.mass * dt
            p.vy -= dt
            p.vz += 2.0 * dt
        }

        for &p in particles
        {
            p.x += dt * p.vx
            p.y += dt * p.vy
            p.z += dt * p.vz
        }
    }
}

#test
{
    // Quarter steps over small integers stay exact, so the expected positions do not
    // depend on how the operations are grouped.
    var particles: [3] Particle = [
        {1.0,  2.0,  3.0,  0.5, -0.5, 0.0,  1.0},
        {-4.0, 0.0,  8.0,  0.0, 1.0,  -1.0, 2.0},
        {0.0,  16.0, -2.0, 2.0, 0.25, 0.75, 3.0}]
    var expected = particles
    for 4
    {
        for &p in expected
        {
            p.vx += p.mass * 0.25
            p.vy -= 0.25
            p.vz += 0.5
            p.x  += 0.25 * p.vx
            p.y  += 0.25 * p.vy
            p.z  += 0.25 * p.vz
        }
    }

    stepParticles(particles, 0.25, 4)
    for i in 3
    {
        Swag.assert(particles[i].x == expected[i].x)
        Swag.assert(particles[i].y == expected[i].y)
        Swag.assert(particles[i].z == expected[i].z)
        Swag.assert(particles[i].vx == expected[i].vx)
        Swag.assert(particles[i].vy == expected[i].vy)
        Swag.assert(particles[i].vz == expected[i].vz)
    }
}
