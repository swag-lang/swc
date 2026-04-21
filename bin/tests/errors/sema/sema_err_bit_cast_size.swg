#global fileprivate

#assert(cast #bit (u64) 1.0'f32 == 0)                   // swc-expected-error {{sema_err_bit_cast_size}}
#assert(cast #bit (f32) 1.0'f64 == 0.0'f32)             // swc-expected-error {{sema_err_bit_cast_size}}
#assert(cast #bit (u32) 1'u64 == 0)                     // swc-expected-error {{sema_err_bit_cast_size}}
#assert(cast #bit (u32) -1.0'f64 == 0xBF800000)         // swc-expected-error {{sema_err_bit_cast_size}}
