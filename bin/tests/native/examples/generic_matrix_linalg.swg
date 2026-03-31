#global fileprivate

// A generic 2x2 matrix toolkit with vector transforms and affine maps.
// Demonstrates non-commutative matrix multiplication, determinants,
// transpose, outer products, and layered generic composition --
// patterns distinct from the component-wise arithmetic in other tests.

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
    func(op: string) opUnary(const me) -> Vec2
    {
        #if op == "-" do
            return {x: -me.x, y: -me.y}
        #else do
            #error("unsupported unary operation [[" ++ op ++ "]]")
    }

    #[Swag.Overload]
    func(op: string) opBinary(const me, other: const &Vec2) -> Vec2
    {
        #if op == "+" do
            return {x: me.x + other.x, y: me.y + other.y}
        #elif op == "-" do
            return {x: me.x - other.x, y: me.y - other.y}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }

    #[Swag.Overload]
    func(op: string) opBinary(const me, scalar: T) -> Vec2
    {
        #if op == "*" do
            return {x: me.x * scalar, y: me.y * scalar}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }

    func dot(a: const &Vec2, b: const &Vec2) -> T
    {
        return a.x * b.x + a.y * b.y
    }

    func lengthSq(const me) -> T
    {
        return me.x * me.x + me.y * me.y
    }

    // 90-degree counter-clockwise rotation
    func perp(const me) -> Vec2
    {
        return {x: -me.y, y: me.x}
    }
}

// ---------------------------------------------------------------------------
// Layer 2: Mat2(T) -- 2x2 matrix, row-major
//
//   | a  b |
//   | c  d |
//
// ---------------------------------------------------------------------------

struct(T) Mat2
{
    a: T
    b: T
    c: T
    d: T
}

impl Mat2
{
    func trace(const me) -> T
    {
        return me.a + me.d
    }

    func det(const me) -> T
    {
        return me.a * me.d - me.b * me.c
    }

    func transpose(const me) -> Mat2
    {
        return {a: me.a, b: me.c, c: me.b, d: me.d}
    }

    func row0(const me) -> Vec2
    {
        return {x: me.a, y: me.b}
    }

    func row1(const me) -> Vec2
    {
        return {x: me.c, y: me.d}
    }

    func col0(const me) -> Vec2
    {
        return {x: me.a, y: me.c}
    }

    func col1(const me) -> Vec2
    {
        return {x: me.b, y: me.d}
    }

    // Linear transform: M * v
    func transform(const me, v: const &Vec2) -> Vec2
    {
        return {x: me.a * v.x + me.b * v.y,
                y: me.c * v.x + me.d * v.y}
    }

    func(op: string) opUnary(const me) -> Mat2
    {
        #if op == "-" do
            return {a: -me.a, b: -me.b, c: -me.c, d: -me.d}
        #else do
            #error("unsupported unary operation [[" ++ op ++ "]]")
    }

    // Mat2 +/- Mat2, Mat2 * Mat2
    #[Swag.Overload]
    func(op: string) opBinary(const me, other: const &Mat2) -> Mat2
    {
        #if op == "+" do
            return {a: me.a + other.a, b: me.b + other.b,
                    c: me.c + other.c, d: me.d + other.d}
        #elif op == "-" do
            return {a: me.a - other.a, b: me.b - other.b,
                    c: me.c - other.c, d: me.d - other.d}
        #elif op == "*" do
            return {a: me.a * other.a + me.b * other.c,
                    b: me.a * other.b + me.b * other.d,
                    c: me.c * other.a + me.d * other.c,
                    d: me.c * other.b + me.d * other.d}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }

    // Mat2 * scalar
    #[Swag.Overload]
    func(op: string) opBinary(const me, scalar: T) -> Mat2
    {
        #if op == "*" do
            return {a: me.a * scalar, b: me.b * scalar,
                    c: me.c * scalar, d: me.d * scalar}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }

    // Build from column vectors
    func fromCols(c0: const &Vec2, c1: const &Vec2) -> Mat2
    {
        return {a: c0.x, b: c1.x, c: c0.y, d: c1.y}
    }

    // Build from row vectors
    func fromRows(r0: const &Vec2, r1: const &Vec2) -> Mat2
    {
        return {a: r0.x, b: r0.y, c: r1.x, d: r1.y}
    }

    // Outer product: v * w^T
    func outer(v: const &Vec2, w: const &Vec2) -> Mat2
    {
        return {a: v.x * w.x, b: v.x * w.y,
                c: v.y * w.x, d: v.y * w.y}
    }
}

// ---------------------------------------------------------------------------
// Layer 3: AffineMap(T) -- maps point p -> mat * p + offset
// ---------------------------------------------------------------------------

struct(T) AffineMap
{
    mat:    Mat2
    offset: Vec2
}

impl AffineMap
{
    func translation(dx: T, dy: T) -> AffineMap
    {
        let one: T = 1
        let z: T = 0
        return {mat: {a: one, b: z, c: z, d: one}, offset: {x: dx, y: dy}}
    }

    func scaling(sx: T, sy: T) -> AffineMap
    {
        let zx: T = 0
        let zy: T = 0
        return {mat: {a: sx, b: zx, c: zy, d: sy}, offset: {x: zx, y: zy}}
    }

    func apply(const me, p: const &Vec2) -> Vec2
    {
        let transformed = me.mat.transform(p)
        return transformed + me.offset
    }

    // Compose: (A after B).  apply(compose(a, b), p) == apply(a, apply(b, p))
    func compose(a: const &AffineMap, b: const &AffineMap) -> AffineMap
    {
        let newMat = a.mat * b.mat
        let rotatedOff = a.mat.transform(&b.offset)
        return {mat: newMat, offset: rotatedOff + a.offset}
    }

    func det(const me) -> T
    {
        return me.mat.det()
    }
}

// ===========================================================================
// Tests: Vec2 perpendicular
// ===========================================================================

#test
{
    var v: Vec2's32 = {x: 3, y: 4}
    @assert(v.lengthSq() == 25)

    var p = v.perp()
    @assert(p.x == -4 and p.y == 3)

    // Perpendicular preserves length
    @assert(p.lengthSq() == 25)

    // Perpendicular is orthogonal
    @assert(Vec2's32.dot(&v, &p) == 0)

    // perp(perp(v)) == -v
    let pp = p.perp()
    @assert(pp.x == -3 and pp.y == -4)
}

// ===========================================================================
// Tests: Mat2 basics
// ===========================================================================

#test
{
    let id: Mat2's32 = {a: 1, b: 0, c: 0, d: 1}
    @assert(id.trace() == 2)
    @assert(id.det() == 1)

    let z: Mat2's32 = {a: 0, b: 0, c: 0, d: 0}
    @assert(z.trace() == 0)
    @assert(z.det() == 0)
}

#test
{
    let m: Mat2's32 = {a: 3, b: 1, c: 2, d: 4}

    @assert(m.det() == 10)  // 3*4 - 1*2
    @assert(m.trace() == 7) // 3 + 4

    let t = m.transpose()
    #assert(#typeof(t) == Mat2's32)
    @assert(t.a == 3 and t.b == 2 and t.c == 1 and t.d == 4)

    // Determinant is invariant under transpose
    @assert(t.det() == m.det())
}

// ===========================================================================
// Tests: Mat2 row/column access
// ===========================================================================

#test
{
    let m: Mat2's32 = {a: 1, b: 2, c: 3, d: 4}

    let r0 = m.row0()
    let r1 = m.row1()
    #assert(#typeof(r0) == Vec2's32)
    @assert(r0.x == 1 and r0.y == 2)
    @assert(r1.x == 3 and r1.y == 4)

    let c0 = m.col0()
    let c1 = m.col1()
    @assert(c0.x == 1 and c0.y == 3)
    @assert(c1.x == 2 and c1.y == 4)
}

// ===========================================================================
// Tests: Mat2 arithmetic
// ===========================================================================

#test
{
    let a: Mat2's32 = {a: 1, b: 2, c: 3, d: 4}
    let b: Mat2's32 = {a: 5, b: 6, c: 7, d: 8}

    let sum = a + b
    @assert(sum.a == 6 and sum.b == 8 and sum.c == 10 and sum.d == 12)

    let diff = b - a
    @assert(diff.a == 4 and diff.b == 4 and diff.c == 4 and diff.d == 4)
}

#test
{
    let m: Mat2's32 = {a: 2, b: -1, c: 3, d: 5}
    let scaled = m * 3's32
    @assert(scaled.a == 6 and scaled.b == -3 and scaled.c == 9 and scaled.d == 15)
}

#test
{
    let m: Mat2's32 = {a: 1, b: -2, c: 3, d: -4}
    let neg = -m
    @assert(neg.a == -1 and neg.b == 2 and neg.c == -3 and neg.d == 4)

    // Double negation is identity
    let nn = -(-m)
    @assert(nn.a == m.a and nn.b == m.b and nn.c == m.c and nn.d == m.d)
}

// ===========================================================================
// Tests: Mat2 * Mat2 (non-commutative)
// ===========================================================================

#test
{
    let a: Mat2's32 = {a: 1, b: 2, c: 3, d: 4}
    let b: Mat2's32 = {a: 5, b: 6, c: 7, d: 8}

    // A * B = | 1*5+2*7  1*6+2*8 | = | 19  22 |
    //         | 3*5+4*7  3*6+4*8 |   | 43  50 |
    let ab = a * b
    @assert(ab.a == 19 and ab.b == 22 and ab.c == 43 and ab.d == 50)

    // B * A = | 5*1+6*3  5*2+6*4 | = | 23  34 |
    //         | 7*1+8*3  7*2+8*4 |   | 31  46 |
    let ba = b * a
    @assert(ba.a == 23 and ba.b == 34 and ba.c == 31 and ba.d == 46)

    // Non-commutative: A*B != B*A
    @assert(ab.a != ba.a or ab.b != ba.b or ab.c != ba.c or ab.d != ba.d)
}

// Identity is the multiplicative neutral element
#test
{
    let id: Mat2's32 = {a: 1, b: 0, c: 0, d: 1}
    let m: Mat2's32 = {a: 7, b: -3, c: 2, d: 11}

    let left = id * m
    @assert(left.a == m.a and left.b == m.b and left.c == m.c and left.d == m.d)

    let right = m * id
    @assert(right.a == m.a and right.b == m.b and right.c == m.c and right.d == m.d)
}

// Associativity: (A*B)*C == A*(B*C)
#test
{
    let a: Mat2's32 = {a: 1, b: 2, c: 0, d: 1}
    let b: Mat2's32 = {a: 3, b: 0, c: 1, d: 2}
    let c: Mat2's32 = {a: -1, b: 4, c: 2, d: 1}

    let ab_c = (a * b) * c
    let a_bc = a * (b * c)

    @assert(ab_c.a == a_bc.a and ab_c.b == a_bc.b)
    @assert(ab_c.c == a_bc.c and ab_c.d == a_bc.d)
}

// det(A*B) == det(A) * det(B)
#test
{
    let a: Mat2's32 = {a: 2, b: 1, c: 3, d: 5}
    let b: Mat2's32 = {a: 4, b: -1, c: 2, d: 3}

    let product = a * b
    @assert(product.det() == a.det() * b.det())
}

// ===========================================================================
// Tests: Mat2 * Vec2 (transform)
// ===========================================================================

#test
{
    let id: Mat2's32 = {a: 1, b: 0, c: 0, d: 1}
    var v: Vec2's32 = {x: 7, y: 13}
    let result = id.transform(&v)

    #assert(#typeof(result) == Vec2's32)
    @assert(result.x == 7 and result.y == 13)
}

// 90-degree CCW rotation via matrix
#test
{
    let rot90: Mat2's32 = {a: 0, b: -1, c: 1, d: 0}

    var v0: Vec2's32 = {x: 1, y: 0}
    var v1 = rot90.transform(&v0)
    @assert(v1.x == 0 and v1.y == 1)

    var v2 = rot90.transform(&v1)
    @assert(v2.x == -1 and v2.y == 0)

    var v3 = rot90.transform(&v2)
    @assert(v3.x == 0 and v3.y == -1)

    var v4 = rot90.transform(&v3)
    @assert(v4.x == 1 and v4.y == 0) // full circle
}

// Scaling transform
#test
{
    let scale: Mat2's32 = {a: 3, b: 0, c: 0, d: 2}
    var v: Vec2's32 = {x: 4, y: 5}
    let result = scale.transform(&v)
    @assert(result.x == 12 and result.y == 10)
}

// Shear transform
#test
{
    let shear: Mat2's32 = {a: 1, b: 2, c: 0, d: 1}
    var v: Vec2's32 = {x: 3, y: 4}
    let result = shear.transform(&v)

    // x' = 1*3 + 2*4 = 11, y' = 0*3 + 1*4 = 4
    @assert(result.x == 11 and result.y == 4)
}

// ===========================================================================
// Tests: Mat2 construction helpers
// ===========================================================================

#test
{
    var c0: Vec2's32 = {x: 1, y: 3}
    var c1: Vec2's32 = {x: 2, y: 4}
    let m = Mat2's32.fromCols(&c0, &c1)

    // row0 = (c0.x, c1.x), row1 = (c0.y, c1.y)
    @assert(m.a == 1 and m.b == 2)
    @assert(m.c == 3 and m.d == 4)

    // Roundtrip: extract columns back
    let ec0 = m.col0()
    let ec1 = m.col1()
    @assert(ec0.x == 1 and ec0.y == 3)
    @assert(ec1.x == 2 and ec1.y == 4)
}

#test
{
    var r0: Vec2's32 = {x: 5, y: 6}
    var r1: Vec2's32 = {x: 7, y: 8}
    let m = Mat2's32.fromRows(&r0, &r1)

    @assert(m.a == 5 and m.b == 6)
    @assert(m.c == 7 and m.d == 8)

    let er0 = m.row0()
    let er1 = m.row1()
    @assert(er0.x == 5 and er0.y == 6)
    @assert(er1.x == 7 and er1.y == 8)
}

// Outer product: v * w^T produces a rank-1 matrix
#test
{
    var v: Vec2's32 = {x: 2, y: 3}
    var w: Vec2's32 = {x: 4, y: 5}
    let m = Mat2's32.outer(&v, &w)

    // | 2*4  2*5 |   | 8   10 |
    // | 3*4  3*5 | = | 12  15 |
    @assert(m.a == 8 and m.b == 10 and m.c == 12 and m.d == 15)

    // Rank-1 matrix has zero determinant
    @assert(m.det() == 0)
}

// ===========================================================================
// Tests: AffineMap
// ===========================================================================

// Pure translation
#test
{
    let t = AffineMap's32.translation(10, -5)
    var p: Vec2's32 = {x: 3, y: 7}
    let result = t.apply(&p)

    #assert(#typeof(result) == Vec2's32)
    @assert(result.x == 13 and result.y == 2)
}

// Pure scaling
#test
{
    let s = AffineMap's32.scaling(3, 2)
    var p: Vec2's32 = {x: 4, y: 5}
    let result = s.apply(&p)

    @assert(result.x == 12 and result.y == 10)
    @assert(s.det() == 6) // 3 * 2
}

// Compose: scale after translate
#test
{
    let translate = AffineMap's32.translation(1, 1)
    let scale     = AffineMap's32.scaling(2, 2)

    // "scale after translate": first translate p, then scale result
    let composed = AffineMap's32.compose(&scale, &translate)
    var p: Vec2's32 = {x: 3, y: 4}

    // translate(3,4) = (4,5), then scale(4,5) = (8,10)
    let result = composed.apply(&p)
    @assert(result.x == 8 and result.y == 10)

    // Verify against step-by-step
    var step1 = translate.apply(&p)
    let step2 = scale.apply(&step1)
    @assert(result.x == step2.x and result.y == step2.y)
}

// Compose: translate after scale (different order, different result)
#test
{
    let translate = AffineMap's32.translation(1, 1)
    let scale     = AffineMap's32.scaling(2, 2)

    // "translate after scale": first scale p, then translate result
    let composed = AffineMap's32.compose(&translate, &scale)
    var p: Vec2's32 = {x: 3, y: 4}

    // scale(3,4) = (6,8), then translate(6,8) = (7,9)
    let result = composed.apply(&p)
    @assert(result.x == 7 and result.y == 9)

    // Composition is non-commutative
    let otherWay = AffineMap's32.compose(&scale, &translate)
    let otherResult = otherWay.apply(&p)
    @assert(result.x != otherResult.x or result.y != otherResult.y)
}

// Compose associativity: (A . B) . C == A . (B . C)
#test
{
    let a = AffineMap's32.translation(10, 0)
    let b = AffineMap's32.scaling(2, 3)
    let c = AffineMap's32.translation(0, -5)

    let ab   = AffineMap's32.compose(&a, &b)
    let ab_c = AffineMap's32.compose(&ab, &c)

    let bc   = AffineMap's32.compose(&b, &c)
    let a_bc = AffineMap's32.compose(&a, &bc)

    var p: Vec2's32 = {x: 1, y: 1}
    let r1 = ab_c.apply(&p)
    let r2 = a_bc.apply(&p)
    @assert(r1.x == r2.x and r1.y == r2.y)
}

// ===========================================================================
// Tests: multi-type instantiation (s64)
// ===========================================================================

#test
{
    let m: Mat2's64 = {a: 100000's64, b: 200000's64, c: 300000's64, d: 400000's64}
    #assert(#typeof(m) == Mat2's64)
    @assert(m.det() == 100000's64 * 400000 - 200000's64 * 300000)

    var v: Vec2's64 = {x: 1000's64, y: 2000's64}
    let result = m.transform(&v)
    #assert(#typeof(result) == Vec2's64)

    // x' = 100000*1000 + 200000*2000 = 500000000
    // y' = 300000*1000 + 400000*2000 = 1100000000
    @assert(result.x == 500000000's64)
    @assert(result.y == 1100000000's64)
}

#test
{
    let t = AffineMap's64.translation(1000000's64, -500000's64)
    var p: Vec2's64 = {x: 42's64, y: 99's64}
    let result = t.apply(&p)

    #assert(#typeof(result) == Vec2's64)
    @assert(result.x == 1000042's64 and result.y == -499901's64)
}
