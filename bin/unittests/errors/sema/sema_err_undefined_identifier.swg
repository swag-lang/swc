#global private

// 'undefined' is now an ordinary identifier, not an initializer escape hatch.
const value: s32 = undefined     // swc-expected-error {{sema_err_unknown_symbol}}
