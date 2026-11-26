#global private

const DivZero0       = 1 / 0         // swc-expected-error {{safety_err_division_zero}}
const DivZeroS8      = 1_s8 / 0      // swc-expected-error {{safety_err_division_zero}}
const DivZeroS16     = 1_s16 / 0     // swc-expected-error {{safety_err_division_zero}}
const DivZeroS32     = 1_s32 / 0     // swc-expected-error {{safety_err_division_zero}}
const DivZeroS64     = 1_s64 / 0     // swc-expected-error {{safety_err_division_zero}}
const DivZeroU8      = 1_u8 / 0      // swc-expected-error {{safety_err_division_zero}}
const DivZeroU16     = 1_u16 / 0     // swc-expected-error {{safety_err_division_zero}}
const DivZeroU32     = 1_u32 / 0     // swc-expected-error {{safety_err_division_zero}}
const DivZeroU64     = 1_u64 / 0     // swc-expected-error {{safety_err_division_zero}}
const DivZeroUnsized = 0 / 0         // swc-expected-error {{safety_err_division_zero}}
const ModZero        = 5 % 0         // swc-expected-error {{safety_err_division_zero}}
