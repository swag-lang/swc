#global fileprivate

// Real-life example: a generic complex number with overloaded unary and binary operators.

struct(T) Complex
{
    re: T
    im: T
}

impl Complex
{
    // Unary +  : identity
    // Unary -  : negate both parts
    func(op: string) opUnary(const me)->Complex'T
    {
        #if op == "+" do
            return {re: +me.re, im: +me.im}
        #elif op == "-" do
            return {re: -me.re, im: -me.im}
        #else do
            #error("unsupported unary operation [[" ++ op ++ "]]")
    }

    // Binary complex op complex
    //   (a+bi) + (c+di) = (a+c) + (b+d)i
    //   (a+bi) - (c+di) = (a-c) + (b-d)i
    //   (a+bi) * (c+di) = (ac-bd) + (ad+bc)i
    func(op: string) opBinary(const me, other: const &Complex'T)->Complex'T
    {
        #if op == "+" do
            return {re: me.re + other.re, im: me.im + other.im}
        #elif op == "-" do
            return {re: me.re - other.re, im: me.im - other.im}
        #elif op == "*" do
            return {re: me.re * other.re - me.im * other.im,
                    im: me.re * other.im + me.im * other.re}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }

    // Binary complex op scalar  (scalar treated as real-only)
    //   (a+bi) + s = (a+s) + bi
    //   (a+bi) - s = (a-s) + bi
    //   (a+bi) * s = (a*s) + (b*s)i
    func(op: string) opBinary(const me, scalar: T)->Complex'T
    {
        #if op == "+" do
            return {re: me.re + scalar, im: me.im}
        #elif op == "-" do
            return {re: me.re - scalar, im: me.im}
        #elif op == "*" do
            return {re: me.re * scalar, im: me.im * scalar}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }

    // Conjugate: (a+bi) -> (a-bi)
    func conjugate(const me)->Complex'T
    {
        return {re: me.re, im: -me.im}
    }

    // Squared magnitude: a*a + b*b
    func normSq(const me)->T
    {
        return me.re * me.re + me.im * me.im
    }
}

// ---------------------------------------------------------------------------
// Unary operator tests
// ---------------------------------------------------------------------------

// Test: unary + preserves both parts
#test
{
    var z: Complex's32 = {re: 3, im: -4}
    let pos = +z

    #assert(#typeof(pos) == Complex's32)
    @assert(pos.re == 3)
    @assert(pos.im == -4)
}

// Test: unary - negates both parts
#test
{
    var z: Complex's32 = {re: 5, im: -7}
    let neg = -z

    @assert(neg.re == -5)
    @assert(neg.im == 7)
}

// Test: double negation is identity
#test
{
    var z: Complex's64 = {re: 42, im: -99}
    let dn = -(-z)

    @assert(dn.re == 42)
    @assert(dn.im == -99)
}

// Test: negation of zero
#test
{
    var z: Complex's32 = {re: 0, im: 0}
    let neg = -z

    @assert(neg.re == 0)
    @assert(neg.im == 0)
}

// ---------------------------------------------------------------------------
// Binary complex + complex tests
// ---------------------------------------------------------------------------

// Test: addition
#test
{
    var a: Complex's32 = {re: 1, im: 2}
    var b: Complex's32 = {re: 3, im: 4}
    let sum = a + b

    #assert(#typeof(sum) == Complex's32)
    @assert(sum.re == 4)
    @assert(sum.im == 6)
}

// Test: subtraction
#test
{
    var a: Complex's32 = {re: 10, im: 20}
    var b: Complex's32 = {re: 3, im: 25}
    let diff = a - b

    @assert(diff.re == 7)
    @assert(diff.im == -5)
}

// Test: multiplication  (1+2i)*(3+4i) = (3-8)+(4+6)i = -5+10i
#test
{
    var a: Complex's32 = {re: 1, im: 2}
    var b: Complex's32 = {re: 3, im: 4}
    let prod = a * b

    @assert(prod.re == -5)
    @assert(prod.im == 10)
}

// Test: multiplication by conjugate yields real (normSq)
//   (3+4i)*(3-4i) = 9+16 = 25, im=0
#test
{
    var z: Complex's32 = {re: 3, im: 4}
    let conj = z.conjugate()
    let prod = z * conj

    @assert(prod.re == 25)
    @assert(prod.im == 0)
}

// Test: multiplication by (0+1i) rotates 90 degrees
//   (a+bi)*(0+1i) = -b + ai
#test
{
    var z: Complex's32 = {re: 5, im: 3}
    var i_unit: Complex's32 = {re: 0, im: 1}
    let rot = z * i_unit

    @assert(rot.re == -3)
    @assert(rot.im == 5)
}

// ---------------------------------------------------------------------------
// Binary complex + scalar tests
// ---------------------------------------------------------------------------

// Test: add scalar shifts real part only
#test
{
    var z: Complex's32 = {re: 2, im: 7}
    let result = z + 10's32

    @assert(result.re == 12)
    @assert(result.im == 7)
}

// Test: subtract scalar
#test
{
    var z: Complex's32 = {re: 5, im: 3}
    let result = z - 8's32

    @assert(result.re == -3)
    @assert(result.im == 3)
}

// Test: multiply by scalar scales both parts
#test
{
    var z: Complex's32 = {re: 2, im: -3}
    let result = z * 4's32

    @assert(result.re == 8)
    @assert(result.im == -12)
}

// Test: multiply by zero scalar
#test
{
    var z: Complex's32 = {re: 99, im: -42}
    let result = z * 0's32

    @assert(result.re == 0)
    @assert(result.im == 0)
}

// ---------------------------------------------------------------------------
// Chaining and combined operations
// ---------------------------------------------------------------------------

// Test: chaining additions
#test
{
    var a: Complex's32 = {re: 1, im: 1}
    var b: Complex's32 = {re: 2, im: 2}
    var c: Complex's32 = {re: 3, im: 3}
    let result = a + b + c

    @assert(result.re == 6)
    @assert(result.im == 6)
}

// Test: add then negate
#test
{
    var a: Complex's32 = {re: 10, im: 20}
    var b: Complex's32 = {re: 5, im: 5}
    let result = -(a + b)

    @assert(result.re == -15)
    @assert(result.im == -25)
}

// Test: z + (-z) == 0
#test
{
    var z: Complex's64 = {re: 123, im: -456}
    let result = z + (-z)

    @assert(result.re == 0)
    @assert(result.im == 0)
}

// Test: scale then subtract
#test
{
    var a: Complex's32 = {re: 6, im: 9}
    var b: Complex's32 = {re: 2, im: 3}
    let result = a - b * 2's32

    @assert(result.re == 2)
    @assert(result.im == 3)
}

// ---------------------------------------------------------------------------
// Helpers: conjugate and normSq
// ---------------------------------------------------------------------------

// Test: conjugate flips sign of imaginary part
#test
{
    var z: Complex's32 = {re: 3, im: 4}
    let conj = z.conjugate()

    @assert(conj.re == 3)
    @assert(conj.im == -4)
}

// Test: conjugate of pure real is itself
#test
{
    var z: Complex's32 = {re: 7, im: 0}
    let conj = z.conjugate()

    @assert(conj.re == 7)
    @assert(conj.im == 0)
}

// Test: double conjugate is identity
#test
{
    var z: Complex's32 = {re: -2, im: 5}
    let cc = z.conjugate().conjugate()

    @assert(cc.re == -2)
    @assert(cc.im == 5)
}

// Test: normSq of 3+4i == 25
#test
{
    var z: Complex's32 = {re: 3, im: 4}
    let n = z.normSq()

    @assert(n == 25)
}

// Test: normSq of pure imaginary
#test
{
    var z: Complex's32 = {re: 0, im: 6}
    let n = z.normSq()

    @assert(n == 36)
}

// Test: normSq of zero
#test
{
    var z: Complex's32 = {re: 0, im: 0}
    let n = z.normSq()

    @assert(n == 0)
}

// ---------------------------------------------------------------------------
// Multiple type instantiations
// ---------------------------------------------------------------------------

// Test: Complex with s64
#test
{
    var a: Complex's64 = {re: 100000, im: -200000}
    var b: Complex's64 = {re: 300000, im: 400000}
    let sum = a + b

    #assert(#typeof(sum) == Complex's64)
    @assert(sum.re == 400000)
    @assert(sum.im == 200000)
}

// Test: Complex with s16
#test
{
    var a: Complex's16 = {re: 10, im: 20}
    var b: Complex's16 = {re: 5, im: -10}
    let prod = a * b

    // (10+20i)*(5-10i) = (50+200)+(−100+100)i = 250+0i
    #assert(#typeof(prod) == Complex's16)
    @assert(prod.re == 250)
    @assert(prod.im == 0)
}

// Test: Complex's64 multiplication associativity spot check
//   a*(b*c) vs (a*b)*c
#test
{
    var a: Complex's64 = {re: 1, im: 2}
    var b: Complex's64 = {re: 3, im: -1}
    var c: Complex's64 = {re: 0, im: 4}

    let lhs = a * (b * c)
    let rhs = (a * b) * c

    @assert(lhs.re == rhs.re)
    @assert(lhs.im == rhs.im)
}
