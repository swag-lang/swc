#global private

// '.count' is not defined for scalar types like bool, floats, or runes.
#assert(true.count == 1)     // swc-expected-error {{sema_err_invalid_countof_type}}
#assert((1.5).count == 1)      // swc-expected-error {{sema_err_invalid_countof_type}}
#assert(('a').count == 1)      // swc-expected-error {{sema_err_invalid_countof_type}}
