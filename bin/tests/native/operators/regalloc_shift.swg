#global fileprivate //

// Stress tests for shift register allocation in the native backend.
//
// On x86-64 the shift count for variable-count shifts must reside in CL (the
// low byte of RCX).  The legalize pass inserts a move-to-CL whenever the
// count is in another physical register.  The register allocator must keep
// all other live values alive across that CL clobber, spilling to the stack
// when necessary.
//
// Unlike the JIT tests, these functions are compiled to native x86-64 and
// executed at runtime, exercising the full encoder + legalize + regalloc
// pipeline.  The loop-based tests create live ranges that span back-edges,
// which generates additional allocation pressure.

// ---------------------------------------------------------------------------
// Test 1 – shift count derived from arithmetic on inputs.
// cnt is computed, so legalize must emit MOV cl, <reg>.
// All five parameters stay live across the shift.
// ---------------------------------------------------------------------------
func shiftCountFromArith(a: u32, b: u32, c: u32, d: u32, e: u32)->u32
{
    var cnt: u32 = b - a    // cnt = 4-1 = 3  (not a literal → CL move required)
    var r: u32 = c << cnt   // 5 << 3 = 40;  a,b,d,e live → RCX/CL pressure
    r += d + e
    return r                // 40 + 2 + 3 = 45
}

// ---------------------------------------------------------------------------
// Test 2 – chain of three shifts each with a different computed count.
// CL must be reloaded for every instruction; a and b must survive each reload.
// ---------------------------------------------------------------------------
func multiShiftChain(x: u32, s1: u32, s2: u32, s3: u32)->u32
{
    var a: u32 = x << s1    // s1 → CL;  a = 1 << 3 = 8
    var b: u32 = a >> s2    // s2 → CL;  b = 8 >> 2 = 2
    var c: u32 = b << s3    // s3 → CL;  c = 2 << 4 = 32
    return a + b + c        // 8 + 2 + 32 = 42
}

// ---------------------------------------------------------------------------
// Test 3 – shifts of u32 and u64 with a shared computed count.
// Tests that the CL constraint is handled correctly for both 32-bit and
// 64-bit shift encodings in the same function body.
// ---------------------------------------------------------------------------
func shiftMixWidths(cnt: u32)->u64
{
    var a: u32 = 0x80'u32   // 128
    var b: u32 = 0x200'u32  // 512
    var c: u64 = 0x800'u64  // 2048
    var ra: u32 = a >> cnt  // 128  >> 2 = 32;   cnt → CL
    var rb: u32 = b >> cnt  // 512  >> 2 = 128;  cnt → CL
    var rc: u64 = c >> cnt  // 2048 >> 2 = 512;  cnt → CL (64-bit encoding)
    return cast(u64) ra + cast(u64) rb + rc  // 32 + 128 + 512 = 672
}

// ---------------------------------------------------------------------------
// Test 4 – shift count lives across a function call.
// RCX is caller-saved on the x86-64 SysV / Windows ABIs; a call between the
// count computation and its use forces the allocator to spill it to the stack
// and reload into CL after the call returns.
// ---------------------------------------------------------------------------
func shiftCallHelper(x: u32, y: u32)->u32 { return x + y }

func shiftLiveAcrossCall(a: u32, b: u32, c: u32)->u32
{
    var cnt: u32 = b - a                 // cnt = 3-1 = 2 (may be in RCX)
    var mid: u32 = shiftCallHelper(a + b, c)  // call clobbers RCX → cnt must spill
    var r: u32 = mid << cnt              // cnt reloaded into CL;  14 << 2 = 56
    return r + a                         // 56 + 1 = 57
}

// ---------------------------------------------------------------------------
// Test 5 – shift count = result of a previous shift (nested CL dependency).
// ---------------------------------------------------------------------------
func nestedShiftCount(x: u32, cnt_base: u32)->u32
{
    var cnt1: u32 = cnt_base       // cnt1 = 2
    var r1: u32 = x << cnt1        // cnt1 → CL;  3 << 2 = 12
    var cnt2: u32 = r1 >> cnt1     // cnt1 → CL;  12 >> 2 = 3  (cnt2 derived from shift)
    var r2: u32 = x << cnt2        // cnt2 → CL;  3 << 3 = 24
    return r1 + r2                 // 12 + 24 = 36
}

// ---------------------------------------------------------------------------
// Test 6 – shift count derived from a division result.
// Division leaves its quotient in RAX; that value must then be copied to CL
// for the subsequent shift.  Both the div-RAX and shift-CL constraints fire.
// ---------------------------------------------------------------------------
func shiftInsideDivExpr(a: u32, b: u32, c: u32)->u32
{
    var cnt: u32 = a / b   // DIV: a=12, b=4 → cnt=3 (in RAX)
    var r: u32 = c << cnt  // SHL: cnt from RAX → CL
    return r               // 5 << 3 = 40
}

// ---------------------------------------------------------------------------
// Test 7 – eight live parameters when the shift executes.
// Forces the allocator to spill around the CL-clobbering shift; the spill
// reload must correctly restore all surviving values.
// ---------------------------------------------------------------------------
func manyLiveShift(a: u32, b: u32, c: u32, d: u32,
                   e: u32, f: u32, g: u32, h: u32)->u32
{
    var cnt: u32 = h - g        // cnt = 4-3 = 1; all 8 params live
    var r: u32 = a << cnt       // 1 << 1 = 2; b,c,d,e,f,g,h still live
    return r + b + c + d + e + f + g + h  // 2+2+3+4+5+6+3+4 = 29
}

// ---------------------------------------------------------------------------
// Test 8 – arithmetic right shift of signed values, variable count.
// SAR must preserve the sign bit; the CL constraint applies identically to
// SAR, so the legalize pass must still emit the CL move.
// ---------------------------------------------------------------------------
func shiftSignedWidths(v: s32, cnt: s32)->s32
{
    var a: s32 = v           // -256
    var b: s32 = v * 4       // -1024
    var c: s32 = v * 16      // -4096
    var ra: s32 = a >> cnt   // cnt → CL; -256  >> 2 = -64   (sign preserved)
    var rb: s32 = b >> cnt   // cnt → CL; -1024 >> 2 = -256
    var rc: s32 = c >> cnt   // cnt → CL; -4096 >> 2 = -1024
    return ra + rb + rc      // -64 + (-256) + (-1024) = -1344
}

// ---------------------------------------------------------------------------
// Test 9 – shift with computed count inside a loop body.
// The shift-count variable's live range spans the loop back-edge; the
// allocator must keep it alive (or spill/reload) on every iteration.
// Additionally cnt is live across the inner shift on each iteration, so the
// register allocator sees a recurring CL conflict at the loop header.
// ---------------------------------------------------------------------------
func shiftInLoop(val: u32, cnt: u32, iters: u32)->u32
{
    var acc: u32 = val     // 32
    var i: u32 = 0'u32
    while i < iters
    {
        acc += acc >> cnt  // cnt → CL on each iteration; acc grows each time
        i += 1'u32
    }
    return acc
    // cnt=2, iters=3:
    //  i=0: acc = 32 + (32>>2)  = 32 + 8  = 40
    //  i=1: acc = 40 + (40>>2)  = 40 + 10 = 50
    //  i=2: acc = 50 + (50>>2)  = 50 + 12 = 62
}

// ---------------------------------------------------------------------------
// Test 10 – left/right shifts with different computed counts in a loop.
// Two shifts with independent count variables interleave in the same loop,
// requiring CL to be written with two distinct values per iteration and both
// count live ranges to coexist across the back-edge.
// ---------------------------------------------------------------------------
func twoCountsInLoop(a: u32, lcnt: u32, rcnt: u32, iters: u32)->u32
{
    var acc: u32 = a      // 1
    var extra: u32 = a    // 1  (kept live alongside acc across the back-edge)
    var i: u32 = 0'u32
    while i < iters
    {
        var shifted: u32 = acc << lcnt   // lcnt → CL
        extra += acc >> rcnt             // rcnt → CL (different value)
        acc = shifted
        i += 1'u32
    }
    return acc + extra
    // a=1, lcnt=3, rcnt=1, iters=2:
    //  i=0: shifted=1<<3=8, extra=1+(1>>1)=1+0=1, acc=8
    //  i=1: shifted=8<<3=64, extra=1+(8>>1)=1+4=5, acc=64
    //  return 64 + 5 = 69
}

#test
{
    @assert(shiftCountFromArith(1'u32, 4'u32, 5'u32, 2'u32, 3'u32) == 45'u32)
}

#test
{
    @assert(multiShiftChain(1'u32, 3'u32, 2'u32, 4'u32) == 42'u32)
}

#test
{
    @assert(shiftMixWidths(2'u32) == 672'u64)
}

#test
{
    @assert(shiftLiveAcrossCall(1'u32, 3'u32, 10'u32) == 57'u32)
}

#test
{
    @assert(nestedShiftCount(3'u32, 2'u32) == 36'u32)
}

#test
{
    @assert(shiftInsideDivExpr(12'u32, 4'u32, 5'u32) == 40'u32)
}

#test
{
    @assert(manyLiveShift(1'u32, 2'u32, 3'u32, 4'u32, 5'u32, 6'u32, 3'u32, 4'u32) == 29'u32)
}

#test
{
    @assert(shiftSignedWidths(-256, 2) == -1344)
}

#test
{
    @assert(shiftInLoop(32'u32, 2'u32, 3'u32) == 62'u32)
}

#test
{
    @assert(twoCountsInLoop(1'u32, 3'u32, 1'u32, 2'u32) == 69'u32)
}
