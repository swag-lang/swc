#global fileprivate

func unresolved() => cast(retval) 1 // swc-expected-error {{sema_err_retval_unknown_return_type}}
