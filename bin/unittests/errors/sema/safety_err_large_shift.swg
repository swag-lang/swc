#global private

// A sized value shifts by an amount below its bit width and nothing else.
#assert(1_u8 << 8 == 0)               // swc-expected-error {{safety_err_large_shift}}
#assert(1_u32 >> 32 == 0)             // swc-expected-error {{safety_err_large_shift}}
#assert((-1_s16) >> 100 == -1)        // swc-expected-error {{safety_err_large_shift}}
#assert(1_u64 << (1 << 100) == 0)     // swc-expected-error {{safety_err_large_shift}}
