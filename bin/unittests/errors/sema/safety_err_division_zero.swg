#global fileprivate

const DivZero0 = 1 / 0                   // swc-expected-error {{safety_err_division_zero}}
const DivZeroS8 = 1's8 / 0               // swc-expected-error {{safety_err_division_zero}}
const DivZeroS16 = 1's16 / 0             // swc-expected-error {{safety_err_division_zero}}
const DivZeroS32 = 1's32 / 0             // swc-expected-error {{safety_err_division_zero}}
const DivZeroS64 = 1's64 / 0             // swc-expected-error {{safety_err_division_zero}}
const DivZeroU8 = 1'u8 / 0               // swc-expected-error {{safety_err_division_zero}}
const DivZeroU16 = 1'u16 / 0             // swc-expected-error {{safety_err_division_zero}}
const DivZeroU32 = 1'u32 / 0             // swc-expected-error {{safety_err_division_zero}}
const DivZeroU64 = 1'u64 / 0             // swc-expected-error {{safety_err_division_zero}}
const DivZeroUnsized = 0 / 0             // swc-expected-error {{safety_err_division_zero}}
const ModZero = 5 % 0                    // swc-expected-error {{safety_err_division_zero}}
