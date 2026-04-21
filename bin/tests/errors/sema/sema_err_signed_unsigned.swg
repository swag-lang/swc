#global fileprivate

// Casting a negative value to an unsigned type is rejected for every unsigned width.
#assert(-10'u32 == -10)                  // swc-expected-error {{sema_err_signed_unsigned}}
#assert(-1'u8  == 255)                   // swc-expected-error {{sema_err_signed_unsigned}}
#assert(-1'u16 == 65535)                 // swc-expected-error {{sema_err_signed_unsigned}}
#assert(-5'u64 == 0)                     // swc-expected-error {{sema_err_signed_unsigned}}
