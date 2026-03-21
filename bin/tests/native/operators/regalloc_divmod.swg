#global fileprivate //

// Stress tests for division / modulo / multiply register allocation in the
// native backend.
//
// On x86-64:
//   IDIV / DIV  – dividend must be in RAX (sign/zero-extended into RDX);
//                 quotient → RAX, remainder → RDX; divisor must NOT be in RDX.
//                 Legalize emits both a fix-to-RAX rewrite and an
//                 away-from-RDX rewrite for the divisor operand.
//   IMUL / MUL  – two-register form clobbers RDX (high half); live values
//                 that happen to be in RDX must be evicted first.
//
// These functions are compiled to native x86-64 and executed at runtime,
// exercising the full encoder + legalize + regalloc pipeline.  Loop tests
// create live ranges that span back-edges for extra allocation pressure.

// ---------------------------------------------------------------------------
// Test 1 – many live variables at the point of division.
// With six parameters all live, one is likely allocated to RDX.  If that
// register happens to hold a divisor, legalize must move it away before DIV.
// ---------------------------------------------------------------------------
func divDivisorInRdx(a: u32, b: u32, c: u32, d: u32, e: u32, f: u32)->u32
{
    var q1: u32 = a / b    // DIV: a=60, b=3 → q1=20; b forbidden from RDX
    var q2: u32 = c / d    // DIV: c=40, d=8 → q2=5;  d forbidden from RDX; e,f live
    return q1 + q2 + e + f // 20 + 5 + 4 + 5 = 34
}

// ---------------------------------------------------------------------------
// Test 2 – a/b and a%b back-to-back.
// Each operation independently requires RAX for input and clobbers RDX;
// the intermediate results q1, r1 must survive the subsequent divides.
// ---------------------------------------------------------------------------
func divModPair(a: u32, b: u32)->u32
{
    var q1: u32 = a / b         // DIV: a=100, b=7 → q1=14 (RAX); RDX clobbered
    var r1: u32 = a % b         // MOD: remainder=2           (RDX); re-clobbered
    var q2: u32 = b / 3'u32     // DIV: 7/3=2; q1,r1 live → spill pressure
    var r2: u32 = b % 3'u32     // MOD: 7%3=1
    return q1 + r1 + q2 + r2   // 14 + 2 + 2 + 1 = 19
}

// ---------------------------------------------------------------------------
// Test 3 – chain of three dependent divisions.
// The quotient of each division feeds the next as dividend; RAX/RDX are
// clobbered three times consecutively.
// ---------------------------------------------------------------------------
func divChain(a: u32, b: u32)->u32
{
    var r1: u32 = a / b    // 120 / 2 = 60
    var r2: u32 = r1 / b   // 60  / 2 = 30
    var r3: u32 = r2 / b   // 30  / 2 = 15
    return r1 + r2 + r3    // 60 + 30 + 15 = 105
}

// ---------------------------------------------------------------------------
// Test 4 – division result used as shift count.
// Quotient in RAX must be transferred to CL for the subsequent SHL.
// Both constraints (div→RAX, shift-count→CL) are active back-to-back.
// ---------------------------------------------------------------------------
func divResultAsShiftCount(a: u32, b: u32, c: u32)->u32
{
    var cnt: u32 = a / b   // DIV: a=12, b=4 → cnt=3 (in RAX); RDX clobbered
    var r: u32 = c << cnt  // SHL: cnt must be in CL → legalize: RAX→CL
    return r               // 5 << 3 = 40
}

// ---------------------------------------------------------------------------
// Test 5 – division and shift interleaved.
// DIV clobbers RAX/RDX; quotient feeds a shift (→CL); a second DIV reuses
// RAX/RDX; then a shift with a derived count uses CL again.
// ---------------------------------------------------------------------------
func divInterleavedShift(a: u32, b: u32, c: u32)->u32
{
    var q: u32  = a / b            // DIV: a=24, b=6 → q=4 (RAX); RDX clobbered
    var s: u32  = c >> q           // SHR: q→CL;  128 >> 4 = 8
    var q2: u32 = c / b            // DIV: RAX reused; 128/6=21; RDX clobbered
    var s2: u32 = a << (q - 1'u32) // SHL: (q-1)→CL=3; 24 << 3 = 192
    return s + q + q2 + s2         // 8 + 4 + 21 + 192 = 225
}

// ---------------------------------------------------------------------------
// Test 6 – mix of IDIV (signed) and DIV (unsigned) instructions.
// Tests correct instruction selection for each numeric type and that the
// RAX/RDX constraints are satisfied for each encoding independently.
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Test 7 – multiply followed by divide using the product.
// MUL writes RDX:RAX; DIV reads RAX and destroys RDX; both share the same
// register pair and must co-operate correctly.
// ---------------------------------------------------------------------------
func mulDivChain(a: u32, b: u32, c: u32)->u32
{
    var p: u32  = a * b      // MUL: a=7, b=8 → p=56 (RDX:RAX; high bits zero)
    var q: u32  = p / c      // DIV: p=56, c=5 → q=11 (RAX); RDX clobbered
    var r: u32  = p % c      // DIV: p=56, c=5 → r=1  (RDX)
    var p2: u32 = q * c      // MUL: 11 * 5 = 55; q,r live → spill pressure
    return p + q + r + p2    // 56 + 11 + 1 + 55 = 123
}

// ---------------------------------------------------------------------------
// Test 8 – (a / b) << (c % d): all three constraints in one expression.
// Quotient (RAX) is the value to shift; remainder (RDX) is the shift count
// (must move to CL).  The legalize pass must sequence RAX→value, RDX→CL
// before encoding the SHL.
// ---------------------------------------------------------------------------
func divInsideShiftExpr(a: u32, b: u32, c: u32, d: u32)->u32
{
    var dividend: u32 = a / b          // DIV: a=80, b=10 → dividend=8 (RAX)
    var shiftCnt: u32 = c % d          // MOD: c=11, d=4  → shiftCnt=3 (RDX→result)
    var r: u32 = dividend << shiftCnt  // SHL: shiftCnt → CL;  8 << 3 = 64
    return r + dividend + shiftCnt     // 64 + 8 + 3 = 75
}

// ---------------------------------------------------------------------------
// Test 9 – division inside a loop body.
// Each iteration: quotient and remainder from DIV feed the accumulator.
// RAX/RDX are clobbered every iteration; live ranges for all loop variables
// span the back-edge, creating sustained allocation pressure.
// ---------------------------------------------------------------------------
func divModInLoop(a: u32, b: u32, iters: u32)->u32
{
    var acc: u32 = a      // 100
    var i: u32 = 0'u32
    while i < iters
    {
        var q: u32 = acc / b   // DIV: RAX constraint; b forbidden from RDX
        var r: u32 = acc % b   // MOD: RDX constraint
        acc = q + r + b        // recombine; loop carries acc across back-edge
        i += 1'u32
    }
    return acc
    // a=100, b=7, iters=3:
    //  i=0: q=14, r=2,  acc=14+2+7  = 23
    //  i=1: q=3,  r=2,  acc=3+2+7   = 12
    //  i=2: q=1,  r=5,  acc=1+5+7   = 13
}

// ---------------------------------------------------------------------------
// Test 10 – multiply and divide alternating in a loop with a live shift count.
// MUL (→RAX/RDX), DIV (→RAX, divisor away from RDX), and SHL (count →CL)
// all appear in the same loop body; every hardware constraint fires on every
// iteration with all loop-carried variables live simultaneously.
// ---------------------------------------------------------------------------
func mulDivShiftInLoop(val: u32, factor: u32, divisor: u32, cnt: u32, iters: u32)->u32
{
    var acc: u32 = val    // 3
    var side: u32 = val   // 3  (kept live across back-edge alongside acc)
    var i: u32 = 0'u32
    while i < iters
    {
        var prod: u32 = acc * factor       // MUL: clobbers RDX; factor != RDX
        var quot: u32 = prod / divisor     // DIV: prod→RAX, divisor away from RDX
        side += quot >> cnt                // SHR: cnt→CL; side carried across back-edge
        acc = quot
        i += 1'u32
    }
    return acc + side
    // val=3, factor=4, divisor=3, cnt=1, iters=3:
    //  i=0: prod=3*4=12, quot=12/3=4, side=3+(4>>1)=3+2=5,   acc=4
    //  i=1: prod=4*4=16, quot=16/3=5, side=5+(5>>1)=5+2=7,   acc=5
    //  i=2: prod=5*4=20, quot=20/3=6, side=7+(6>>1)=7+3=10,  acc=6
    //  return 6 + 10 = 16
}

#test
{
    @assert(divDivisorInRdx(60'u32, 3'u32, 40'u32, 8'u32, 4'u32, 5'u32) == 34'u32)
}

#test
{
    @assert(divModPair(100'u32, 7'u32) == 19'u32)
}

#test
{
    @assert(divChain(120'u32, 2'u32) == 105'u32)
}

#test
{
    @assert(divResultAsShiftCount(12'u32, 4'u32, 5'u32) == 40'u32)
}

#test
{
    @assert(divInterleavedShift(24'u32, 6'u32, 128'u32) == 225'u32)
}

#test
{
    @assert(signedUnsignedDivMix(-90, 60'u32, 420's64) == 22's64)
}

#test
{
    @assert(mulDivChain(7'u32, 8'u32, 5'u32) == 123'u32)
}

#test
{
    @assert(divInsideShiftExpr(80'u32, 10'u32, 11'u32, 4'u32) == 75'u32)
}

#test
{
    @assert(divModInLoop(100'u32, 7'u32, 3'u32) == 13'u32)
}

#test
{
    @assert(mulDivShiftInLoop(3'u32, 4'u32, 3'u32, 1'u32, 3'u32) == 16'u32)
}
