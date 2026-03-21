#global fileprivate

// Stress tests for shift register allocation.
//
// On x86-64 the shift count must reside in CL (the low byte of RCX) for
// variable-count shifts.  The legalize pass inserts a move-to-CL whenever the
// count is held in a different physical register; the register allocator must
// then keep all other live values alive across that clobber.
//
// Every test here uses a *computed* count (never an immediate literal) so the
// constraint is always exercised, and keeps many values live simultaneously to
// maximise allocation pressure.

// ---------------------------------------------------------------------------
// Test 1 – shift count derived from arithmetic on inputs.
// cnt is computed, so legalize must emit MOV cl, <reg>.
// d and e stay live across the shift, forcing the allocator to place them in
// registers other than RCX.
// ---------------------------------------------------------------------------
#test
{
    func shiftCountFromArith(a: u32, b: u32, c: u32, d: u32, e: u32)->u32
    {
        var cnt: u32 = b - a    // cnt = 4-1 = 3  (computed, not literal)
        var r: u32 = c << cnt   // 5 << 3 = 40;  a,b,d,e live → RCX/CL conflict
        r += d + e
        return r
    }

    // cnt=3, 5<<3=40, 40+2+3=45
    const V = #run shiftCountFromArith(1'u32, 4'u32, 5'u32, 2'u32, 3'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 45'u32)
}

// ---------------------------------------------------------------------------
// Test 2 – chain of three shifts each with a *different* computed count.
// CL must be reloaded for every shift; intermediate values a and b must
// survive each reload.
// ---------------------------------------------------------------------------
#test
{
    func multiShiftChain(x: u32, s1: u32, s2: u32, s3: u32)->u32
    {
        var a: u32 = x << s1    // s1 → CL;  a = 1 << 3 = 8
        var b: u32 = a >> s2    // s2 → CL;  b = 8 >> 2 = 2
        var c: u32 = b << s3    // s3 → CL;  c = 2 << 4 = 32
        return a + b + c        // 8 + 2 + 32 = 42
    }

    const V = #run multiShiftChain(1'u32, 3'u32, 2'u32, 4'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 42'u32)
}

// ---------------------------------------------------------------------------
// Test 3 – shifts of u32 and u64 with a shared computed count.
// Tests that the CL constraint is handled correctly for both 32-bit and
// 64-bit shift encodings in the same function.
// ---------------------------------------------------------------------------
#test
{
    func shiftMixWidths(cnt: u32)->u64
    {
        var a: u32 = 0x80'u32   // 128
        var b: u32 = 0x200'u32  // 512
        var c: u64 = 0x800'u64  // 2048
        var ra: u32 = a >> cnt  // 128  >> 2 = 32;   cnt → CL
        var rb: u32 = b >> cnt  // 512  >> 2 = 128;  cnt → CL
        var rc: u64 = c >> cnt  // 2048 >> 2 = 512;  cnt → CL (64-bit)
        return cast(u64) ra + cast(u64) rb + rc  // 32 + 128 + 512 = 672
    }

    const V = #run shiftMixWidths(2'u32)
    #assert(#typeof(V) == u64)
    #assert(V == 672'u64)
}

// ---------------------------------------------------------------------------
// Test 4 – shift count lives across a function call.
// A call may clobber RCX (caller-saved); the allocator must spill cnt before
// the call and reload it into CL afterwards.
// ---------------------------------------------------------------------------
#test
{
    func addHelper(x: u32, y: u32)->u32 { return x + y }

    func shiftLiveAcrossCall(a: u32, b: u32, c: u32)->u32
    {
        var cnt: u32 = b - a                 // cnt = 3-1 = 2 (in some reg, maybe RCX)
        var mid: u32 = addHelper(a + b, c)   // call may clobber RCX → cnt must survive
        var r: u32 = mid << cnt              // cnt reloaded into CL;  14 << 2 = 56
        return r + a                         // 56 + 1 = 57
    }

    const V = #run shiftLiveAcrossCall(1'u32, 3'u32, 10'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 57'u32)
}

// ---------------------------------------------------------------------------
// Test 5 – shift count = result of a previous shift (nested CL dependency).
// r1 is produced by shift[cnt1→CL], then r1 itself becomes cnt2 for the next
// shift, requiring CL to be written twice with different values.
// ---------------------------------------------------------------------------
#test
{
    func nestedShiftCount(x: u32, cnt_base: u32)->u32
    {
        var cnt1: u32 = cnt_base        // cnt1 = 2
        var r1: u32 = x << cnt1         // cnt1 → CL;  3 << 2 = 12
        var cnt2: u32 = r1 >> cnt1      // cnt1 → CL;  12 >> 2 = 3  (cnt2 derived from shift)
        var r2: u32 = x << cnt2         // cnt2 → CL;  3 << 3 = 24
        return r1 + r2                  // 12 + 24 = 36
    }

    const V = #run nestedShiftCount(3'u32, 2'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 36'u32)
}

// ---------------------------------------------------------------------------
// Test 6 – shift count derived from a division result.
// Division leaves its result in RAX; that value must then be moved to CL for
// the shift.  Both the div-RAX and shift-CL constraints fire in sequence.
// ---------------------------------------------------------------------------
#test
{
    func shiftInsideDivExpr(a: u32, b: u32, c: u32)->u32
    {
        var cnt: u32 = a / b   // DIV: a=12, b=4 → cnt=3 (lands in RAX)
        var r: u32 = c << cnt  // SHL: cnt from RAX → must move to CL
        return r               // 5 << 3 = 40
    }

    const V = #run shiftInsideDivExpr(12'u32, 4'u32, 5'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 40'u32)
}

// ---------------------------------------------------------------------------
// Test 7 – eight live variables when the shift executes.
// With all general-purpose registers occupied, the allocator is forced to
// spill around the CL-clobbering shift.
// ---------------------------------------------------------------------------
#test
{
    func manyLiveShift(a: u32, b: u32, c: u32, d: u32,
                       e: u32, f: u32, g: u32, h: u32)->u32
    {
        var cnt: u32 = h - g        // cnt = 4-3 = 1; all 8 params live
        var r: u32 = a << cnt       // 1 << 1 = 2; b,c,d,e,f,g,h still live → spill pressure
        return r + b + c + d + e + f + g + h  // 2+2+3+4+5+6+3+4 = 29
    }

    const V = #run manyLiveShift(1'u32, 2'u32, 3'u32, 4'u32, 5'u32, 6'u32, 3'u32, 4'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 29'u32)
}

// ---------------------------------------------------------------------------
// Test 8 – arithmetic right shift of signed values, variable count.
// Checks that the SAR instruction is emitted (sign bit replicated) and that
// the CL constraint is satisfied for each signed-width shift.
// ---------------------------------------------------------------------------
#test
{
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

    const V = #run shiftSignedWidths(-256, 2)
    #assert(#typeof(V) == s32)
    #assert(V == -1344)
}
