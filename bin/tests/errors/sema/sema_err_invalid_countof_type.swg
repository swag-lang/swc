#global fileprivate

// '@countof' is not defined for scalar types like bool, floats, or runes.
#assert(@countof(true) == 1)             // swc-expected-error {{sema_err_invalid_countof_type}}
#assert(@countof(1.5) == 1)              // swc-expected-error {{sema_err_invalid_countof_type}}
#assert(@countof('a') == 1)              // swc-expected-error {{sema_err_invalid_countof_type}}
