#global fileprivate

const InvalidWrapDiv = 1 / #wrap 4                  // swc-expected-error {{sema_err_modifier_unsupported}}
const InvalidBitDiv = 1 / #bit 4                    // swc-expected-error {{sema_err_modifier_unsupported}}
const InvalidWrapInc = 1 ++ #wrap 4                 // swc-expected-error {{sema_err_modifier_unsupported}}
#assert(1 ^ #wrap 0 == 1)                           // swc-expected-error {{sema_err_modifier_unsupported}}
#assert(1 & #wrap 0 == 1)                           // swc-expected-error {{sema_err_modifier_unsupported}}
#assert(1 | #wrap 0 == 1)                           // swc-expected-error {{sema_err_modifier_unsupported}}
