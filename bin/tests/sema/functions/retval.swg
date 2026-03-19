#global fileprivate

var GlobalRetVal: retval // swc-expected-error {{sema_err_retval_outside_function}}

func unresolved() => cast(retval) 1 // swc-expected-error {{sema_err_retval_unknown_return_type}}
