#global fileprivate

// Stress tests for division / modulo / multiply register allocation.
//
// On x86-64:
//   IDIV / DIV  – dividend must be in RAX (high bits zero/sign-extended into
//                 RDX); quotient → RAX, remainder → RDX; the *divisor* must
//                 NOT reside in RDX.  The legalize pass enforces both the
//                 fix-to-RAX and the away-from-RDX rewrites.
//   IMUL / MUL  – the two-operand form clobbers RDX (high bits); the compiler
//                 must keep live values out of RDX around the instruction.
//
// Every test here keeps extra variables live during the constrained
// instruction to maximise register pressure and trigger spill/reload paths.

// ---------------------------------------------------------------------------
// Test 1 – many live variables at the point of division.
// With six parameters occupying registers the allocator will likely place the
// divisors (b, d) in RDX, which IDIV forbids.  Legalize must move them away.
// ---------------------------------------------------------------------------
#test
{
    func divDivisorInRdx(a: u32, b: u32, c: u32, d: u32, e: u32, f: u32)->u32
    {
        // b is the divisor for the first div; d for the second.
        // With 6 live values competing for registers, one of them will be
        // allocated to RDX.  The legalize pass must evict whichever divisor
        // lands there before emitting DIV.
        var q1: u32 = a / b    // DIV: a=60, b=3 → q1=20;  b forbidden from RDX
        var q2: u32 = c / d    // DIV: c=40, d=8 → q2=5;   d forbidden from RDX
        return q1 + q2 + e + f // 20 + 5 + 4 + 5 = 34
    }

    const V = #run divDivisorInRdx(60'u32, 3'u32, 40'u32, 8'u32, 4'u32, 5'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 34'u32)
}

// ---------------------------------------------------------------------------
// Test 2 – a/b and a%b back-to-back with the same operands.
// Each operation independently clobbers RAX and RDX; q1 must survive the
// second div that computes r1, and both must survive the third and fourth.
// ---------------------------------------------------------------------------
#test
{
    func divModPair(a: u32, b: u32)->u32
    {
        var q1: u32 = a / b         // DIV: a=100, b=7 → q1=14  (RAX); RDX clobbered
        var r1: u32 = a % b         // DIV: remainder=2           (RDX); RAX/RDX re-clobbered
        var q2: u32 = b / 3'u32     // DIV: 7/3=2; q1,r1 still live → spill pressure
        var r2: u32 = b % 3'u32     // DIV: 7%3=1
        return q1 + r1 + q2 + r2   // 14 + 2 + 2 + 1 = 19
    }

    const V = #run divModPair(100'u32, 7'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 19'u32)
}

// ---------------------------------------------------------------------------
// Test 3 – chain of three dependent divisions.
// Each division clobbers RAX/RDX; the quotient of one feeds the next, so the
// allocator must correctly thread the live range through repeated clobbers.
// ---------------------------------------------------------------------------
#test
{
    func divChain(a: u32, b: u32)->u32
    {
        var r1: u32 = a / b    // 120 / 2 = 60
        var r2: u32 = r1 / b   // 60  / 2 = 30
        var r3: u32 = r2 / b   // 30  / 2 = 15
        return r1 + r2 + r3    // 60 + 30 + 15 = 105
    }

    const V = #run divChain(120'u32, 2'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 105'u32)
}

// ---------------------------------------------------------------------------
// Test 4 – division result used as shift count.
// The quotient (in RAX after DIV) becomes the shift-count operand, which must
// end up in CL for SHL.  Both the div-RAX and shift-CL constraints fire in
// immediate succession; legalize must emit the RAX→CL transfer.
// ---------------------------------------------------------------------------
#test
{
    func divResultAsShiftCount(a: u32, b: u32, c: u32)->u32
    {
        var cnt: u32 = a / b   // DIV: a=12, b=4 → cnt=3 (in RAX); RDX clobbered
        var r: u32 = c << cnt  // SHL: cnt must be in CL → legalize: RAX→CL
        return r               // 5 << 3 = 40
    }

    const V = #run divResultAsShiftCount(12'u32, 4'u32, 5'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 40'u32)
}

// ---------------------------------------------------------------------------
// Test 5 – division and shift interleaved.
// DIV clobbers RAX/RDX; the quotient is then used as a shift count (→ CL);
// a second DIV reuses RAX/RDX; and a shift with a derived count uses CL again.
// All three register constraints are active in close succession.
// ---------------------------------------------------------------------------
#test
{
    func divInterleavedShift(a: u32, b: u32, c: u32)->u32
    {
        var q: u32  = a / b           // DIV: a=24, b=6 → q=4 (RAX); RDX clobbered
        var s: u32  = c >> q          // SHL: q→CL;  128 >> 4 = 8
        var q2: u32 = c / b           // DIV: RAX reused; 128/6=21; RDX clobbered
        var s2: u32 = a << (q - 1'u32) // SHL: (q-1)→CL=3; 24 << 3 = 192
        return s + q + q2 + s2        // 8 + 4 + 21 + 192 = 225
    }

    const V = #run divInterleavedShift(24'u32, 6'u32, 128'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 225'u32)
}

// ---------------------------------------------------------------------------
// Test 6 – mix of signed (IDIV) and unsigned (DIV) divisions.
// Tests that the backend selects IDIV for s32/s64 and DIV for u32, and that
// the RAX/RDX constraints are satisfied for each encoding independently.
// ---------------------------------------------------------------------------
#test
{
    func signedUnsignedDivMix(a: s32, b: u32, big: s64)->s64
    {
        var sq: s32 = a / 3          // IDIV32:  -90 / 3  = -30
        var sr: s32 = a % 7          // IDIV32:  -90 % 7  = -6  (truncated toward 0)
        var uq: u32 = b / 5'u32      // DIV32:    60 / 5  = 12
        var ur: u32 = b % 7'u32      // DIV32:    60 % 7  = 4
        var bq: s64 = big / 10's64   // IDIV64:  420 / 10 = 42
        return cast(s64) sq + cast(s64) sr + cast(s64) uq + cast(s64) ur + bq
        // -30 + (-6) + 12 + 4 + 42 = 22
    }

    const V = #run signedUnsignedDivMix(-90, 60'u32, 420's64)
    #assert(#typeof(V) == s64)
    #assert(V == 22's64)
}

// ---------------------------------------------------------------------------
// Test 7 – multiply followed by divide using the product.
// MUL clobbers RDX (high half); DIV then requires the product in RAX.
// Both instructions share RAX/RDX, so the allocator must thread correctly.
// ---------------------------------------------------------------------------
#test
{
    func mulDivChain(a: u32, b: u32, c: u32)->u32
    {
        var p: u32  = a * b      // MUL: a=7, b=8 → p=56 (RDX:RAX; high bits zero)
        var q: u32  = p / c      // DIV: p=56, c=5 → q=11 (RAX); RDX clobbered
        var r: u32  = p % c      // DIV: p=56, c=5 → r=1  (RDX)
        var p2: u32 = q * c      // MUL: 11 * 5 = 55 (RAX; q,r live → spill pressure)
        return p + q + r + p2    // 56 + 11 + 1 + 55 = 123
    }

    const V = #run mulDivChain(7'u32, 8'u32, 5'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 123'u32)
}

// ---------------------------------------------------------------------------
// Test 8 – (a / b) << (c % d): div feeds shift value, mod feeds shift count.
// The quotient (RAX after DIV) is the value to be shifted; the remainder
// (RDX after MOD) becomes the shift count (→ CL).  Three distinct hardware
// register constraints materialise from a single compound expression.
// ---------------------------------------------------------------------------
#test
{
    func divInsideShiftExpr(a: u32, b: u32, c: u32, d: u32)->u32
    {
        var dividend: u32 = a / b          // DIV: a=80, b=10 → dividend=8  (RAX)
        var shiftCnt: u32 = c % d          // MOD: c=11, d=4  → shiftCnt=3  (RDX→result)
        var r: u32 = dividend << shiftCnt  // SHL: shiftCnt → CL;  8 << 3 = 64
        return r + dividend + shiftCnt     // 64 + 8 + 3 = 75
    }

    const V = #run divInsideShiftExpr(80'u32, 10'u32, 11'u32, 4'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 75'u32)
}
