#global fileprivate

// A small 2D physics simulation toolkit built entirely on generic structs.
// Demonstrates heavy use of generic argument deduction: inside impl blocks,
// return types and parameter types omit 'T when the compiler can deduce it.

// ---------------------------------------------------------------------------
// Layer 1: Vec2(T)
// ---------------------------------------------------------------------------

struct(T) Vec2
{
    x: T
    y: T
}

impl Vec2
{
    func(op: string) opUnary(const me)->Vec2
    {
        #if op == "-" do
            return {x: -me.x, y: -me.y}
        #else do
            #error("unsupported unary operation [[" ++ op ++ "]]")
    }

    func(op: string) opBinary(const me, other: const &Vec2)->Vec2
    {
        #if op == "+" do
            return {x: me.x + other.x, y: me.y + other.y}
        #elif op == "-" do
            return {x: me.x - other.x, y: me.y - other.y}
        #elif op == "*" do
            return {x: me.x * other.x, y: me.y * other.y}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }

    func(op: string) opBinary(const me, scalar: T)->Vec2
    {
        #if op == "*" do
            return {x: me.x * scalar, y: me.y * scalar}
        #elif op == "/" do
            return {x: me.x / scalar, y: me.y / scalar}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }

    func dot(a: const &Vec2, b: const &Vec2)->T
    {
        return a.x * b.x + a.y * b.y
    }

    func lengthSq(const me)->T
    {
        return me.x * me.x + me.y * me.y
    }

    func lerp(a: const &Vec2, b: const &Vec2, t: T)->Vec2
    {
        let one: T = 1
        return {x: a.x * (one - t) + b.x * t,
                y: a.y * (one - t) + b.y * t}
    }

    func min(a: const &Vec2, b: const &Vec2)->Vec2
    {
        return {x: @min(a.x, b.x), y: @min(a.y, b.y)}
    }

    func max(a: const &Vec2, b: const &Vec2)->Vec2
    {
        return {x: @max(a.x, b.x), y: @max(a.y, b.y)}
    }

    func clamp(v: const &Vec2, lo: const &Vec2, hi: const &Vec2)->Vec2
    {
        return {x: @min(@max(v.x, lo.x), hi.x),
                y: @min(@max(v.y, lo.y), hi.y)}
    }
}

// ---------------------------------------------------------------------------
// Layer 2: AABB(T) -- axis-aligned bounding box
// ---------------------------------------------------------------------------

struct(T) AABB
{
    lo: Vec2
    hi: Vec2
}

impl AABB
{
    func width(const me)->T   => me.hi.x - me.lo.x
    func height(const me)->T  => me.hi.y - me.lo.y
    func area(const me)->T    => me.width() * me.height()

    func center(const me)->Vec2
    {
        return {x: (me.lo.x + me.hi.x) / 2, y: (me.lo.y + me.hi.y) / 2}
    }

    func halfExtent(const me)->Vec2
    {
        return {x: me.width() / 2, y: me.height() / 2}
    }

    func contains(const me, point: const &Vec2)->bool
    {
        return point.x >= me.lo.x and point.x <= me.hi.x and
               point.y >= me.lo.y and point.y <= me.hi.y
    }

    func overlaps(const me, other: const &AABB)->bool
    {
        return me.lo.x <= other.hi.x and me.hi.x >= other.lo.x and
               me.lo.y <= other.hi.y and me.hi.y >= other.lo.y
    }

    func expand(const me, margin: T)->AABB
    {
        return {lo: {x: me.lo.x - margin, y: me.lo.y - margin},
                hi: {x: me.hi.x + margin, y: me.hi.y + margin}}
    }

    func merge(a: const &AABB, b: const &AABB)->AABB
    {
        return {lo: Vec2.min(&a.lo, &b.lo),
                hi: Vec2.max(&a.hi, &b.hi)}
    }

    func(op: string) opBinary(const me, offset: const &Vec2)->AABB
    {
        #if op == "+" do
            return {lo: me.lo + offset, hi: me.hi + offset}
        #elif op == "-" do
            return {lo: me.lo - offset, hi: me.hi - offset}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }

    func(op: string) opBinary(const me, scalar: T)->AABB
    {
        #if op == "*" do
            return {lo: me.lo * scalar, hi: me.hi * scalar}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }
}

// ---------------------------------------------------------------------------
// Layer 3: Particle(T) -- moving body with position, velocity, acceleration
// ---------------------------------------------------------------------------

struct(T) Particle
{
    pos: Vec2
    vel: Vec2
    acc: Vec2
    mass: T
}

impl Particle
{
    // Euler step: v += a*dt, p += v*dt
    func step(const me, dt: T)->Particle
    {
        let newVel = me.vel + me.acc * dt
        let newPos = me.pos + newVel * dt
        return {pos: newPos, vel: newVel, acc: me.acc, mass: me.mass}
    }

    func applyForce(const me, force: const &Vec2)->Particle
    {
        let newAcc = me.acc + force * (1 / me.mass)
        return {pos: me.pos, vel: me.vel, acc: newAcc, mass: me.mass}
    }

    func resetAcceleration(const me)->Particle
    {
        let zeroAcc: Vec2 = me.acc * 0
        return {pos: me.pos, vel: me.vel, acc: zeroAcc, mass: me.mass}
    }

    func kineticEnergy(const me)->T
    {
        return me.vel.lengthSq() * me.mass / 2
    }

    func momentum(const me)->Vec2
    {
        return me.vel * me.mass
    }

    func bounds(const me, radius: T)->AABB
    {
        return {lo: {x: me.pos.x - radius, y: me.pos.y - radius},
                hi: {x: me.pos.x + radius, y: me.pos.y + radius}}
    }
}

// ---------------------------------------------------------------------------
// Layer 4: Spring(T) -- connects two particles
// ---------------------------------------------------------------------------

struct(T) Spring
{
    a:        Particle
    b:        Particle
    stiffness: T
    restLen:   T
}

impl Spring
{
    func separation(const me)->Vec2
    {
        return me.b.pos - me.a.pos
    }

    func distanceSq(const me)->T
    {
        let sep = me.separation()
        return sep.lengthSq()
    }

    // Crude spring force (no sqrt). Pushes both particles.
    func applySpringForce(const me)->Spring
    {
        let sep   = me.separation()
        let distSq = sep.lengthSq()

        // Force magnitude proportional to displacement squared
        let forceMag = me.stiffness * (distSq - me.restLen * me.restLen)

        // Direction approximation using separation vector directly
        let forceOnA: Vec2 = sep * forceMag
        let forceOnB: Vec2 = -forceOnA

        return {a:         me.a.applyForce(&forceOnA),
                b:         me.b.applyForce(&forceOnB),
                stiffness: me.stiffness,
                restLen:   me.restLen}
    }

    func step(const me, dt: T)->Spring
    {
        return {a:         me.a.step(dt),
                b:         me.b.step(dt),
                stiffness: me.stiffness,
                restLen:   me.restLen}
    }

    func totalKineticEnergy(const me)->T
    {
        return me.a.kineticEnergy() + me.b.kineticEnergy()
    }

    func totalMomentum(const me)->Vec2
    {
        return me.a.momentum() + me.b.momentum()
    }

    func systemBounds(const me, radius: T)->AABB
    {
        let boundsA = me.a.bounds(radius)
        let boundsB = me.b.bounds(radius)
        return AABB.merge(&boundsA, &boundsB)
    }
}

// ===========================================================================
// Tests: Vec2
// ===========================================================================

#test
{
    var a: Vec2's32 = {x: 3, y: 4}
    var b: Vec2's32 = {x: 1, y: -2}

    let sum = a + b
    @assert(sum.x == 4 and sum.y == 2)

    let diff = a - b
    @assert(diff.x == 2 and diff.y == 6)

    let scaled = a * 3's32
    @assert(scaled.x == 9 and scaled.y == 12)

    let d = Vec2's32.dot(&a, &b)
    @assert(d == -5) // 3*1 + 4*(-2)

    @assert(a.lengthSq() == 25) // 9 + 16
}

#test
{
    var lo: Vec2's32  = {x: 1, y: 2}
    var hi: Vec2's32  = {x: 10, y: 20}
    let mid = Vec2's32.lerp(&lo, &hi, 0's32)
    @assert(mid.x == 1 and mid.y == 2)

    let end = Vec2's32.lerp(&lo, &hi, 1's32)
    @assert(end.x == 10 and end.y == 20)
}

#test
{
    var a: Vec2's32 = {x: 3, y: 10}
    var b: Vec2's32 = {x: 7, y: 2}
    let mn = Vec2's32.min(&a, &b)
    let mx = Vec2's32.max(&a, &b)
    @assert(mn.x == 3 and mn.y == 2)
    @assert(mx.x == 7 and mx.y == 10)
}

#test
{
    var v: Vec2's32  = {x: 15, y: -5}
    var lo: Vec2's32 = {x: 0, y: 0}
    var hi: Vec2's32 = {x: 10, y: 10}
    let c = Vec2's32.clamp(&v, &lo, &hi)
    @assert(c.x == 10 and c.y == 0)
}

// ===========================================================================
// Tests: AABB
// ===========================================================================

#test
{
    let box: AABB's32 = {lo: {x: 0, y: 0}, hi: {x: 10, y: 6}}

    @assert(box.width() == 10)
    @assert(box.height() == 6)
    @assert(box.area() == 60)

    let c = box.center()
    #assert(#typeof(c) == Vec2's32)
    @assert(c.x == 5 and c.y == 3)

    let h = box.halfExtent()
    @assert(h.x == 5 and h.y == 3)
}

#test
{
    let box: AABB's32 = {lo: {x: 0, y: 0}, hi: {x: 10, y: 10}}
    var inside: Vec2's32  = {x: 5, y: 5}
    var outside: Vec2's32 = {x: 11, y: 5}

    @assert(box.contains(&inside))
    @assert(!box.contains(&outside))
}

#test
{
    let a: AABB's32 = {lo: {x: 0, y: 0}, hi: {x: 10, y: 10}}
    let b: AABB's32 = {lo: {x: 5, y: 5}, hi: {x: 15, y: 15}}
    let c: AABB's32 = {lo: {x: 20, y: 20}, hi: {x: 30, y: 30}}

    @assert(a.overlaps(&b))
    @assert(!a.overlaps(&c))
}

#test
{
    let box: AABB's32 = {lo: {x: 0, y: 0}, hi: {x: 10, y: 10}}
    let expanded = box.expand(2's32)
    @assert(expanded.lo.x == -2 and expanded.lo.y == -2)
    @assert(expanded.hi.x == 12 and expanded.hi.y == 12)
}

#test
{
    let a: AABB's32 = {lo: {x: 0, y: 0}, hi: {x: 5, y: 5}}
    let b: AABB's32 = {lo: {x: 3, y: 3}, hi: {x: 10, y: 10}}
    let m = AABB's32.merge(&a, &b)
    @assert(m.lo.x == 0 and m.lo.y == 0)
    @assert(m.hi.x == 10 and m.hi.y == 10)
}

#test
{
    let box: AABB's32 = {lo: {x: 0, y: 0}, hi: {x: 10, y: 10}}
    var offset: Vec2's32 = {x: 5, y: -3}
    let moved = box + offset
    #assert(#typeof(moved) == AABB's32)
    @assert(moved.lo.x == 5 and moved.lo.y == -3)
    @assert(moved.hi.x == 15 and moved.hi.y == 7)
    @assert(moved.area() == box.area())
}

#test
{
    let box: AABB's32 = {lo: {x: 1, y: 2}, hi: {x: 3, y: 4}}
    let scaled = box * 10's32
    @assert(scaled.lo.x == 10 and scaled.lo.y == 20)
    @assert(scaled.hi.x == 30 and scaled.hi.y == 40)
}

// ===========================================================================
// Tests: Particle
// ===========================================================================

#test
{
    let p: Particle's32 = {pos: {x: 0, y: 0}, vel: {x: 10, y: 0}, acc: {x: 0, y: 0}, mass: 1}
    let p1 = p.step(1's32)

    @assert(p1.pos.x == 10 and p1.pos.y == 0)
    @assert(p1.vel.x == 10 and p1.vel.y == 0)
}

#test
{
    let p: Particle's32 = {pos: {x: 0, y: 0}, vel: {x: 0, y: 0}, acc: {x: 0, y: -10}, mass: 1}
    let p1 = p.step(1's32)

    // v += a*dt = (0,-10), p += v*dt = (0,-10)
    @assert(p1.vel.x == 0 and p1.vel.y == -10)
    @assert(p1.pos.x == 0 and p1.pos.y == -10)
}

#test
{
    let p: Particle's32 = {pos: {x: 0, y: 0}, vel: {x: 0, y: 0}, acc: {x: 0, y: 0}, mass: 1}
    var force: Vec2's32 = {x: 10, y: 5}
    let p1 = p.applyForce(&force)

    // acc += force/mass = (10, 5) since mass=1
    @assert(p1.acc.x == 10 and p1.acc.y == 5)
}

#test
{
    let p: Particle's32 = {pos: {x: 0, y: 0}, vel: {x: 3, y: 4}, acc: {x: 0, y: 0}, mass: 2}
    @assert(p.kineticEnergy() == 25) // (9+16)*2/2

    let mom = p.momentum()
    #assert(#typeof(mom) == Vec2's32)
    @assert(mom.x == 6 and mom.y == 8) // vel*mass
}

#test
{
    let p: Particle's32 = {pos: {x: 5, y: 5}, vel: {x: 0, y: 0}, acc: {x: 0, y: 0}, mass: 1}
    let b = p.bounds(2's32)
    #assert(#typeof(b) == AABB's32)
    @assert(b.lo.x == 3 and b.lo.y == 3)
    @assert(b.hi.x == 7 and b.hi.y == 7)
}

#test
{
    let p: Particle's32 = {pos: {x: 0, y: 0}, vel: {x: 1, y: 1}, acc: {x: 5, y: -5}, mass: 1}
    let p1 = p.resetAcceleration()
    @assert(p1.acc.x == 0 and p1.acc.y == 0)
    @assert(p1.vel.x == 1 and p1.vel.y == 1)
}

// ===========================================================================
// Tests: Spring
// ===========================================================================

#test
{
    let s: Spring's32 = {
        a:         {pos: {x: 0, y: 0}, vel: {x: 0, y: 0}, acc: {x: 0, y: 0}, mass: 1},
        b:         {pos: {x: 10, y: 0}, vel: {x: 0, y: 0}, acc: {x: 0, y: 0}, mass: 1},
        stiffness: 1,
        restLen:   5}

    let sep = s.separation()
    #assert(#typeof(sep) == Vec2's32)
    @assert(sep.x == 10 and sep.y == 0)
    @assert(s.distanceSq() == 100)
}

#test
{
    let s: Spring's32 = {
        a:         {pos: {x: 0, y: 0}, vel: {x: 3, y: 0}, acc: {x: 0, y: 0}, mass: 2},
        b:         {pos: {x: 10, y: 0}, vel: {x: -3, y: 0}, acc: {x: 0, y: 0}, mass: 2},
        stiffness: 1,
        restLen:   5}

    @assert(s.totalKineticEnergy() == 18) // (9*2/2)*2

    let mom = s.totalMomentum()
    @assert(mom.x == 0 and mom.y == 0) // 6 + (-6)
}

#test
{
    let s: Spring's32 = {
        a:         {pos: {x: 0, y: 0}, vel: {x: 0, y: 0}, acc: {x: 0, y: 0}, mass: 1},
        b:         {pos: {x: 10, y: 0}, vel: {x: 0, y: 0}, acc: {x: 0, y: 0}, mass: 1},
        stiffness: 1,
        restLen:   5}

    let bounds = s.systemBounds(1's32)
    #assert(#typeof(bounds) == AABB's32)
    @assert(bounds.lo.x == -1 and bounds.lo.y == -1)
    @assert(bounds.hi.x == 11 and bounds.hi.y == 1)
}

// ===========================================================================
// Tests: multi-type instantiation
// ===========================================================================

#test
{
    var a: Vec2's64 = {x: 100000's64, y: -200000's64}
    var b: Vec2's64 = {x: 300000's64, y: 400000's64}
    let sum = a + b
    #assert(#typeof(sum) == Vec2's64)
    @assert(sum.x == 400000 and sum.y == 200000)
}

#test
{
    let box: AABB's64 = {lo: {x: 0's64, y: 0's64}, hi: {x: 1000000's64, y: 500000's64}}
    @assert(box.area() == 500000000000's64)
    let c = box.center()
    #assert(#typeof(c) == Vec2's64)
    @assert(c.x == 500000 and c.y == 250000)
}

#test
{
    let p: Particle's64 = {pos: {x: 0's64, y: 0's64}, vel: {x: 100's64, y: 0's64}, acc: {x: 0's64, y: -10's64}, mass: 5's64}
    let p1 = p.step(2's64)
    // v = (100, -20), p = (200, -40)
    @assert(p1.vel.x == 100 and p1.vel.y == -20)
    @assert(p1.pos.x == 200 and p1.pos.y == -40)
}
