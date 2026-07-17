#global private

// '#nonull' is restricted to types that can otherwise carry a null value.
var Value: #nonull bool // swc-expected-error {{sema_err_bad_type_qualifier}}
