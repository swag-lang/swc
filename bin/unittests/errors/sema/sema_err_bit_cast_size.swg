#global private

#assert(cast #bit (u64, 1.0_f32) == 0)               // swc-expected-error {{sema_err_bit_cast_size}}
#assert(cast #bit (f32, 1.0_f64) == 0.0_f32)         // swc-expected-error {{sema_err_bit_cast_size}}
#assert(cast #bit (u32, -1.0_f64) == 0xBF800000)     // swc-expected-error {{sema_err_bit_cast_size}}
