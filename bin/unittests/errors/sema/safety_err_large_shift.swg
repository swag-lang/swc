#global private

// A sized value shifts by an amount below its bit width and nothing else.
#assert(1'u8 << 8 == 0)              // swc-expected-error {{safety_err_large_shift}}
#assert(1'u32 >> 32 == 0)            // swc-expected-error {{safety_err_large_shift}}
#assert((-1's16) >> 100 == -1)       // swc-expected-error {{safety_err_large_shift}}
#assert(1'u64 << (1 << 100) == 0)    // swc-expected-error {{safety_err_large_shift}}
