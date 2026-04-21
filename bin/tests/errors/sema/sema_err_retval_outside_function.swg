#global fileprivate

// 'retval' is only legal inside a function body.
var a: retval                    // swc-expected-error {{sema_err_retval_outside_function}}
const b: retval = undefined      // swc-expected-error {{sema_err_retval_outside_function}}
