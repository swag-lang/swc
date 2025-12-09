#assert(cast #bit (u32) -1.0'f64 == 0xBF800000)         // swc-expected-error {{sema_err_bit_cast_size}}
#assert(cast #bit (bool) -1.0'f64 == 0xBF800000)        // swc-expected-error {{sema_err_bit_cast_invalid_type}}

#assert(cast #bit (u32) -1.0'f32 == 0xBF800000)