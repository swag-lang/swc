#global fileprivate

const AA: s32    // swc-expected-error {{sema_err_const_missing_init}}
const A1, B1: s32 = undefined // swc-expected-error {{sema_err_const_missing_init}}
