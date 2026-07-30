#global private

// Casting a negative value to an unsigned type is rejected for every unsigned width.
#assert(-10'u32 == -10)      // swc-expected-error {{sema_err_signed_unsigned}}
#assert(-1'u8  == 255)       // swc-expected-error {{sema_err_signed_unsigned}}
#assert(-1'u16 == 65535)     // swc-expected-error {{sema_err_signed_unsigned}}
#assert(-5'u64 == 0)         // swc-expected-error {{sema_err_signed_unsigned}}

// The same rejection applies when the conversion comes from operand promotion rather than
// from a suffix. Promoting a negative into the unsigned winner used to fold to the wrapped
// value, while the very same expression raises an overflow panic once the operand is not
// known at compile time.
#assert(0'u8 + (-1's8) == 255)        // swc-expected-error {{sema_err_signed_unsigned}}
#assert(0'u16 + (-1's8) == 65535)     // swc-expected-error {{sema_err_signed_unsigned}}
#assert(0'u32 + (-1's16) == 0)        // swc-expected-error {{sema_err_signed_unsigned}}
#assert(0'u64 + (-1's64) == 0)        // swc-expected-error {{sema_err_signed_unsigned}}

// Comparisons promote the same way, so they are rejected the same way. This one used to
// answer 'false' on the wrapped value.
#assert(-1's8 < 0'u8)     // swc-expected-error {{sema_err_signed_unsigned}}

// A positive operand promotes as before: the winner can hold it.
#assert(0'u8 + 1's8 == 1)
#assert(#typeof(0'u8 + 1's8) == u8)
