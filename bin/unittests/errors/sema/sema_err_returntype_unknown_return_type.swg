#global private

func unresolved() => cast(#returntype, 1)     // swc-expected-error {{sema_err_returntype_unknown_return_type}}
