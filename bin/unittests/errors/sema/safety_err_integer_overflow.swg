#global fileprivate

const OverflowAddS8 = 127's8 + 1's8         // swc-expected-error {{safety_err_integer_overflow}}
const OverflowAddU8 = 255'u8 + 1'u8         // swc-expected-error {{safety_err_integer_overflow}}
const OverflowSubU8 = 0'u8 - 1'u8           // swc-expected-error {{safety_err_integer_overflow}}
const OverflowSubS8 = -128's8 - 1's8        // swc-expected-error {{safety_err_integer_overflow}}
const OverflowMulS16 = 32767's16 * 2's16    // swc-expected-error {{safety_err_integer_overflow}}
const OverflowMulU16 = 65535'u16 * 2'u16    // swc-expected-error {{safety_err_integer_overflow}}

const DivOverflowS32 = -2147483648's32 / -1           // swc-expected-error {{safety_err_integer_overflow}}
const DivOverflowS64 = -9223372036854775808's64 / -1  // swc-expected-error {{safety_err_integer_overflow}}
