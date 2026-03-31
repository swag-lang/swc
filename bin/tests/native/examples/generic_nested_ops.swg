#global fileprivate

// Real-life example: nested generic structs with operator overloads.
// A 2D geometry toolkit where higher-level types compose lower-level ones
// and operators propagate through the nesting.

// ---------------------------------------------------------------------------
// Layer 1: Vec2(T) -- basic 2D vector
// ---------------------------------------------------------------------------

struct(T) Vec2
{
    x: T
    y: T
}

impl Vec2
{
    func(op: string) opUnary(const me)->Vec2'T
    {
        #if op == "+" do
            return {x: +me.x, y: +me.y}
        #elif op == "-" do
            return {x: -me.x, y: -me.y}
        #else do
            #error("unsupported unary operation [[" ++ op ++ "]]")
    }

    #[Swag.Overload]
    func(op: string) opBinary(const me, other: const &Vec2'T)->Vec2'T
    {
        #if op == "+" do
            return {x: me.x + other.x, y: me.y + other.y}
        #elif op == "-" do
            return {x: me.x - other.x, y: me.y - other.y}
        #elif op == "*" do
            return {x: me.x * other.x, y: me.y * other.y}
        #elif op == "/" do
            return {x: me.x / other.x, y: me.y / other.y}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }

    #[Swag.Overload]
    func(op: string) opBinary(const me, scalar: T)->Vec2'T
    {
        #if op == "+" do
            return {x: me.x + scalar, y: me.y + scalar}
        #elif op == "-" do
            return {x: me.x - scalar, y: me.y - scalar}
        #elif op == "*" do
            return {x: me.x * scalar, y: me.y * scalar}
        #elif op == "/" do
            return {x: me.x / scalar, y: me.y / scalar}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }

    func dot(a: const &Vec2'T, b: const &Vec2'T)->T
    {
        return a.x * b.x + a.y * b.y
    }
}

// ---------------------------------------------------------------------------
// Layer 2: Rect(T) -- axis-aligned rectangle from two Vec2'T corners
// ---------------------------------------------------------------------------

struct(T) Rect
{
    min: Vec2'T
    max: Vec2'T
}

impl Rect
{
    // Unary -: reflect the rectangle through the origin
    func(op: string) opUnary(const me)->Rect'T
    {
        #if op == "-" do
            return {min: -me.max, max: -me.min}
        #else do
            #error("unsupported unary operation [[" ++ op ++ "]]")
    }

    // Rect + Vec2 = translate,  Rect + Rect = bounding union
    #[Swag.Overload]
    func(op: string) opBinary(const me, offset: const &Vec2'T)->Rect'T
    {
        #if op == "+" do
            return {min: me.min + offset, max: me.max + offset}
        #elif op == "-" do
            return {min: me.min - offset, max: me.max - offset}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }

    // Rect * scalar = scale from origin
    #[Swag.Overload]
    func(op: string) opBinary(const me, scalar: T)->Rect'T
    {
        #if op == "*" do
            return {min: me.min * scalar, max: me.max * scalar}
        #elif op == "/" do
            return {min: me.min / scalar, max: me.max / scalar}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }

    func width(const me)->T  => me.max.x - me.min.x
    func height(const me)->T => me.max.y - me.min.y
    func area(const me)->T   => me.width() * me.height()

    func center(const me)->Vec2'T
    {
        return {x: (me.min.x + me.max.x) / 2, y: (me.min.y + me.max.y) / 2}
    }
}

// ---------------------------------------------------------------------------
// Layer 3: Transform2D(T) -- position + scale, both as Vec2'T
// ---------------------------------------------------------------------------

struct(T) Transform2D
{
    pos:   Vec2'T
    scale: Vec2'T
}

impl Transform2D
{
    // Unary -: negate position, keep scale
    func(op: string) opUnary(const me)->Transform2D'T
    {
        #if op == "-" do
            return {pos: -me.pos, scale: me.scale}
        #else do
            #error("unsupported unary operation [[" ++ op ++ "]]")
    }

    // Combine two transforms: add positions, multiply scales
    #[Swag.Overload]
    func(op: string) opBinary(const me, other: const &Transform2D'T)->Transform2D'T
    {
        #if op == "+" do
            return {pos: me.pos + other.pos, scale: me.scale * other.scale}
        #elif op == "-" do
            return {pos: me.pos - other.pos, scale: me.scale * other.scale}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }

    // Uniform scale: multiply both pos and scale by scalar
    #[Swag.Overload]
    func(op: string) opBinary(const me, scalar: T)->Transform2D'T
    {
        #if op == "*" do
            return {pos: me.pos * scalar, scale: me.scale * scalar}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }

    // Apply transform to a point
    func apply(const me, point: const &Vec2'T)->Vec2'T
    {
        return {x: point.x * me.scale.x + me.pos.x,
                y: point.y * me.scale.y + me.pos.y}
    }

    // Apply transform to a rectangle
    func applyRect(const me, rect: const &Rect'T)->Rect'T
    {
        return {min: {x: rect.min.x * me.scale.x + me.pos.x,
                      y: rect.min.y * me.scale.y + me.pos.y},
                max: {x: rect.max.x * me.scale.x + me.pos.x,
                      y: rect.max.y * me.scale.y + me.pos.y}}
    }
}

// ---------------------------------------------------------------------------
// Layer 4: Pair(A, B) -- heterogeneous pair with component-wise ops
// ---------------------------------------------------------------------------

struct(A, B) Pair
{
    first: A
    second: B
}

// ===========================================================================
// Tests: Vec2 basics
// ===========================================================================

// Test: Vec2 unary + and -
#test
{
    var v: Vec2's32 = {x: 3, y: -7}
    let pos = +v
    let neg = -v

    @assert(pos.x == 3)
    @assert(pos.y == -7)
    @assert(neg.x == -3)
    @assert(neg.y == 7)
}

// Test: Vec2 + Vec2
#test
{
    var a: Vec2's32 = {x: 1, y: 2}
    var b: Vec2's32 = {x: 10, y: 20}
    let sum = a + b

    #assert(#typeof(sum) == Vec2's32)
    @assert(sum.x == 11)
    @assert(sum.y == 22)
}

// Test: Vec2 * scalar
#test
{
    var v: Vec2's32 = {x: 5, y: -3}
    let scaled = v * 4's32

    @assert(scaled.x == 20)
    @assert(scaled.y == -12)
}

// Test: Vec2 dot product
#test
{
    var a: Vec2's32 = {x: 3, y: 4}
    var b: Vec2's32 = {x: 4, y: -3}
    let d = Vec2's32.dot(&a, &b)

    // 12 + (-12) = 0  (perpendicular)
    @assert(d == 0)
}

// ===========================================================================
// Tests: Rect (nested Vec2'T fields)
// ===========================================================================

// Test: Rect dimensions and area
#test
{
    let r: Rect's32 = {min: {x: 0, y: 0}, max: {x: 10, y: 5}}

    @assert(r.width() == 10)
    @assert(r.height() == 5)
    @assert(r.area() == 50)
}

// Test: Rect center
#test
{
    let r: Rect's32 = {min: {x: 0, y: 0}, max: {x: 20, y: 10}}
    let c = r.center()

    @assert(c.x == 10)
    @assert(c.y == 5)
}

// Test: Rect + Vec2 (translate)
#test
{
    let r: Rect's32 = {min: {x: 0, y: 0}, max: {x: 10, y: 10}}
    var offset: Vec2's32 = {x: 5, y: -3}
    let moved = r + offset

    @assert(moved.min.x == 5)
    @assert(moved.min.y == -3)
    @assert(moved.max.x == 15)
    @assert(moved.max.y == 7)
    // Dimensions preserved
    @assert(moved.width() == 10)
    @assert(moved.height() == 10)
}

// Test: Rect - Vec2 (translate back)
#test
{
    let r: Rect's32 = {min: {x: 5, y: 5}, max: {x: 15, y: 15}}
    var offset: Vec2's32 = {x: 5, y: 5}
    let moved = r - offset

    @assert(moved.min.x == 0)
    @assert(moved.min.y == 0)
    @assert(moved.max.x == 10)
    @assert(moved.max.y == 10)
}

// Test: Rect * scalar (scale from origin)
#test
{
    let r: Rect's32 = {min: {x: 1, y: 2}, max: {x: 3, y: 4}}
    let scaled = r * 10's32

    @assert(scaled.min.x == 10)
    @assert(scaled.min.y == 20)
    @assert(scaled.max.x == 30)
    @assert(scaled.max.y == 40)
    @assert(scaled.area() == r.area() * 100)
}

// Test: Rect / scalar
#test
{
    let r: Rect's32 = {min: {x: 10, y: 20}, max: {x: 30, y: 40}}
    let shrunk = r / 10's32

    @assert(shrunk.min.x == 1)
    @assert(shrunk.min.y == 2)
    @assert(shrunk.max.x == 3)
    @assert(shrunk.max.y == 4)
}

// Test: unary - on Rect (reflect through origin)
#test
{
    let r: Rect's32 = {min: {x: 2, y: 3}, max: {x: 8, y: 7}}
    let reflected = -r

    // -max becomes new min, -min becomes new max
    @assert(reflected.min.x == -8)
    @assert(reflected.min.y == -7)
    @assert(reflected.max.x == -2)
    @assert(reflected.max.y == -3)
    // Dimensions preserved
    @assert(reflected.width() == r.width())
    @assert(reflected.height() == r.height())
}

// Test: translate then scale (chaining)
#test
{
    let r: Rect's32 = {min: {x: 0, y: 0}, max: {x: 4, y: 2}}
    var offset: Vec2's32 = {x: 1, y: 1}
    let result = (r + offset) * 3's32

    // After translate: min={1,1}, max={5,3}
    // After scale:     min={3,3}, max={15,9}
    @assert(result.min.x == 3)
    @assert(result.min.y == 3)
    @assert(result.max.x == 15)
    @assert(result.max.y == 9)
}

// ===========================================================================
// Tests: Transform2D (nested Vec2'T fields + operates on Vec2/Rect)
// ===========================================================================

// Test: apply identity transform to a point
#test
{
    let identity: Transform2D's32 = {pos: {x: 0, y: 0}, scale: {x: 1, y: 1}}
    var p: Vec2's32 = {x: 7, y: 13}
    let result = identity.apply(&p)

    @assert(result.x == 7)
    @assert(result.y == 13)
}

// Test: apply translation-only transform
#test
{
    let t: Transform2D's32 = {pos: {x: 10, y: -5}, scale: {x: 1, y: 1}}
    var p: Vec2's32 = {x: 3, y: 4}
    let result = t.apply(&p)

    @assert(result.x == 13)
    @assert(result.y == -1)
}

// Test: apply scale-only transform
#test
{
    let t: Transform2D's32 = {pos: {x: 0, y: 0}, scale: {x: 2, y: 3}}
    var p: Vec2's32 = {x: 5, y: 10}
    let result = t.apply(&p)

    @assert(result.x == 10)
    @assert(result.y == 30)
}

// Test: apply full transform (scale then translate)
#test
{
    let t: Transform2D's32 = {pos: {x: 100, y: 200}, scale: {x: 3, y: 4}}
    var p: Vec2's32 = {x: 1, y: 1}
    let result = t.apply(&p)

    // 1*3 + 100 = 103, 1*4 + 200 = 204
    @assert(result.x == 103)
    @assert(result.y == 204)
}

// Test: apply transform to a Rect
#test
{
    let t: Transform2D's32 = {pos: {x: 10, y: 10}, scale: {x: 2, y: 2}}
    var r: Rect's32 = {min: {x: 0, y: 0}, max: {x: 5, y: 3}}
    let result = t.applyRect(&r)

    // min: 0*2+10=10, 0*2+10=10
    // max: 5*2+10=20, 3*2+10=16
    @assert(result.min.x == 10)
    @assert(result.min.y == 10)
    @assert(result.max.x == 20)
    @assert(result.max.y == 16)
}

// Test: combine two transforms with +
#test
{
    let a: Transform2D's32 = {pos: {x: 10, y: 20}, scale: {x: 2, y: 3}}
    let b: Transform2D's32 = {pos: {x: 5, y: -5},  scale: {x: 4, y: 2}}
    let combined = a + b

    // pos: 10+5=15, 20+(-5)=15
    // scale: 2*4=8, 3*2=6
    @assert(combined.pos.x == 15)
    @assert(combined.pos.y == 15)
    @assert(combined.scale.x == 8)
    @assert(combined.scale.y == 6)
}

// Test: negate transform then combine
#test
{
    let t: Transform2D's32 = {pos: {x: 10, y: 20}, scale: {x: 2, y: 3}}
    let inv = -t

    @assert(inv.pos.x == -10)
    @assert(inv.pos.y == -20)
    // Scale preserved under negation
    @assert(inv.scale.x == 2)
    @assert(inv.scale.y == 3)
}

// Test: transform * scalar
#test
{
    let t: Transform2D's32 = {pos: {x: 3, y: 4}, scale: {x: 1, y: 2}}
    let result = t * 5's32

    @assert(result.pos.x == 15)
    @assert(result.pos.y == 20)
    @assert(result.scale.x == 5)
    @assert(result.scale.y == 10)
}

// ===========================================================================
// Tests: cross-layer interactions and deeper nesting
// ===========================================================================

// Test: Pair of two Rects with independent ops
#test
{
    let left: Rect's32 = {min: {x: 0, y: 0}, max: {x: 10, y: 10}}
    let right: Rect's32 = {min: {x: 20, y: 20}, max: {x: 30, y: 30}}
    let p: Pair'(Rect's32, Rect's32) = {first: left, second: right}

    @assert(p.first.area() == 100)
    @assert(p.second.area() == 100)
    @assert(p.first.center().x == 5)
    @assert(p.second.center().x == 25)
}

// Test: Pair of Transform2D and Rect -- apply first to second
#test
{
    let t: Transform2D's32 = {pos: {x: 100, y: 100}, scale: {x: 2, y: 2}}
    let r: Rect's32 = {min: {x: 0, y: 0}, max: {x: 5, y: 5}}
    let scene: Pair'(Transform2D's32, Rect's32) = {first: t, second: r}
    let world = scene.first.applyRect(&scene.second)

    @assert(world.min.x == 100)
    @assert(world.min.y == 100)
    @assert(world.max.x == 110)
    @assert(world.max.y == 110)
}

// Test: translated Rect applied through combined transform
#test
{
    let t1: Transform2D's32 = {pos: {x: 10, y: 0}, scale: {x: 1, y: 1}}
    let t2: Transform2D's32 = {pos: {x: 0, y: 10}, scale: {x: 2, y: 2}}
    let combined = t1 + t2

    var r: Rect's32 = {min: {x: 1, y: 1}, max: {x: 3, y: 3}}
    let result = combined.applyRect(&r)

    // combined: pos={10,10}, scale={2,2}
    // min: 1*2+10=12, 1*2+10=12
    // max: 3*2+10=16, 3*2+10=16
    @assert(result.min.x == 12)
    @assert(result.min.y == 12)
    @assert(result.max.x == 16)
    @assert(result.max.y == 16)
    @assert(result.area() == 16)
}

// Test: reflect Rect, translate, check center
#test
{
    let r: Rect's32 = {min: {x: 2, y: 4}, max: {x: 6, y: 8}}
    var offset: Vec2's32 = {x: 10, y: 10}
    let result = (-r) + offset

    // Reflected: min={-6,-8}, max={-2,-4}
    // Translated: min={4,2}, max={8,6}
    @assert(result.min.x == 4)
    @assert(result.min.y == 2)
    @assert(result.max.x == 8)
    @assert(result.max.y == 6)
    @assert(result.center().x == 6)
    @assert(result.center().y == 4)
}

// ===========================================================================
// Tests: multiple type instantiations
// ===========================================================================

// Test: Vec2 with s64
#test
{
    var a: Vec2's64 = {x: 100000, y: -200000}
    var b: Vec2's64 = {x: 300000, y: 400000}
    let sum = a + b

    #assert(#typeof(sum) == Vec2's64)
    @assert(sum.x == 400000)
    @assert(sum.y == 200000)
}

// Test: Rect with s64
#test
{
    let r: Rect's64 = {min: {x: 0, y: 0}, max: {x: 1000000, y: 500000}}

    #assert(#typeof(r.min) == Vec2's64)
    @assert(r.area() == 500000000000's64)
}

// Test: Transform2D with s16 applied to Vec2
#test
{
    let t: Transform2D's16 = {pos: {x: 10, y: 20}, scale: {x: 2, y: 3}}
    var p: Vec2's16 = {x: 5, y: 4}
    let result = t.apply(&p)

    #assert(#typeof(result) == Vec2's16)
    @assert(result.x == 20)
    @assert(result.y == 32)
}
