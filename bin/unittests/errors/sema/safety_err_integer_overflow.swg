#global private

const OverflowAddS8  = 127_s8 + 1_s8         // swc-expected-error {{safety_err_integer_overflow}}
const OverflowAddU8  = 255_u8 + 1_u8         // swc-expected-error {{safety_err_integer_overflow}}
const OverflowSubU8  = 0_u8 - 1_u8           // swc-expected-error {{safety_err_integer_overflow}}
const OverflowSubS8  = -128_s8 - 1_s8        // swc-expected-error {{safety_err_integer_overflow}}
const OverflowMulS16 = 32767_s16 * 2_s16     // swc-expected-error {{safety_err_integer_overflow}}
const OverflowMulU16 = 65535_u16 * 2_u16     // swc-expected-error {{safety_err_integer_overflow}}

const DivOverflowS32 = -2147483648_s32 / -1     // swc-expected-error {{safety_err_integer_overflow}}
const DivOverflowS64 = -9223372036854775808_s64 / -1     // swc-expected-error {{safety_err_integer_overflow}}
