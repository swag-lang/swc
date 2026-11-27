#global private

// Casting a negative value to an unsigned type is rejected for every unsigned width.
#assert(-10_u32 == -10)      // swc-expected-error {{sema_err_signed_unsigned}}
#assert(-1_u8 == 255)        // swc-expected-error {{sema_err_signed_unsigned}}
#assert(-1_u16 == 65535)     // swc-expected-error {{sema_err_signed_unsigned}}
#assert(-5_u64 == 0)         // swc-expected-error {{sema_err_signed_unsigned}}

// The same rejection applies when the conversion comes from operand promotion rather than
// from a suffix. Promoting a negative into the unsigned winner used to fold to the wrapped
// value, while the very same expression raises an overflow panic once the operand is not
// known at compile time.
#assert(0_u8 + (-1_s8) == 255)        // swc-expected-error {{sema_err_signed_unsigned}}
#assert(0_u16 + (-1_s8) == 65535)     // swc-expected-error {{sema_err_signed_unsigned}}
#assert(0_u32 + (-1_s16) == 0)        // swc-expected-error {{sema_err_signed_unsigned}}
#assert(0_u64 + (-1_s64) == 0)        // swc-expected-error {{sema_err_signed_unsigned}}

// Comparisons promote the same way, so they are rejected the same way. This one used to
// answer 'false' on the wrapped value.
#assert(-1_s8 < 0_u8)     // swc-expected-error {{sema_err_signed_unsigned}}

// A positive operand promotes as before: the winner can hold it.
#assert(0_u8 + 1_s8 == 1)
#assert(#typeof(0_u8 + 1_s8) == u8)
