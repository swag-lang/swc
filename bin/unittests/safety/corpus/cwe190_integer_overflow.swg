#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-190 / CWE-191 - Integer overflow and underflow
//
// The result does not fit the type. In C on a signed type this is undefined behavior, which
// is what makes it a memory-safety class rather than a numeric one: the optimizer is entitled
// to assume it cannot happen, and a bounds check written after an overflowing addition can be
// deleted.
//
// Swag: NOT undefined. Overflow is a runtime panic wherever '.Overflow' is on, and defined
// wrapping where it is off - so the optimizer can never build on it, in any configuration.
// '#wrap' asks for wrapping explicitly, and '#prom' widens instead.
//
// Proven cases are rejected at compile time even where the guard is off, which is what keeps
// the constant-folding half honest.
// -----------------------------------------------------------------------------

// --- Faults ---

#[Swag.Safety(.Overflow, true)]
func addOverflowsS8(left, right: s8)->s8
{
    return left + right     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run addOverflowsS8(opaqueS8(127), opaqueS8(1))
}

#[Swag.Safety(.Overflow, true)]
func multiplyOverflowsS32(left, right: s32)->s32
{
    return left * right     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run multiplyOverflowsS32(opaqueS32(65536), opaqueS32(65536))
}

// Unsigned subtraction below zero is the underflow half (CWE-191), and the same guard.
#[Swag.Safety(.Overflow, true)]
func subtractUnderflowsU8(left, right: u8)->u8
{
    return left - right     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run subtractUnderflowsU8(opaqueU8(0), opaqueU8(1))
}

// The classic C exploit shape: a size computed by multiplication wraps, the allocation is
// small, and the loop that follows writes the size the caller asked for. The overflow is
// caught before any of that.
#[Swag.Safety(.Overflow, true)]
func allocationSizeOverflows(count, elementSize: u32)->u32
{
    return count * elementSize     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run allocationSizeOverflows(opaqueU32(0x1000_0000), opaqueU32(0x40))
}

// Dividing the minimum signed value by -1 has no representable result. This one is PROVEN,
// so it is reported even with the runtime guard off.
#[Swag.Safety(.Overflow, false), Swag.Sanity(.Overflow, true)]
func divideMinimumByMinusOne()->s32
{
    var value = Swag.S32.Min
    value /= -1     // swc-expected-error {{sanity_err_integer_overflow}}
    return value
}

#test
{
    #run divideMinimumByMinusOne()
}

// --- Sound ---

// '#wrap' asks for the wrapping result, and gets it without a panic.
#[Swag.Safety(.Overflow, true)]
func wrapsOnRequest(value: u8)->u8
{
    return value + #wrap 1
}

// '#prom' widens the operands instead of wrapping them.
func promotesOnRequest()->u32
{
    let result = 255'u8 + #prom 1
    #assert(#typeof(result) == u32)
    return result
}

// A shift discards bits by definition, so it is not an overflow.
#[Swag.Safety(.Overflow, true)]
func shiftDiscardsBits(value: u8)->u8
{
    return value << 1
}

#test
{
    Swag.assert(wrapsOnRequest(opaqueU8(255)) == 0)
    Swag.assert(promotesOnRequest() == 256)
    Swag.assert(shiftDiscardsBits(opaqueU8(255)) == 254)
}
