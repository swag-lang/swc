#global private

#assert(cast #bit (bool, -1.0'f64) == 0xBF800000)     // swc-expected-error {{sema_err_bit_cast_invalid_type}}
#assert(cast #bit (bool, 1'u8) == true)     // swc-expected-error {{sema_err_bit_cast_invalid_type}}

const ShortArray: [3] u32 = [1, 2, 3]
const ShortVector         = cast #bit(#simd [4] u32, ShortArray)     // swc-expected-error {{sema_err_bit_cast_invalid_type}}
