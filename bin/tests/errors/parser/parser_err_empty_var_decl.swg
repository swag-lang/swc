#global fileprivate

// A declaration needs ':' <type> or '=' <value>; missing both is an error.
const A 0                              // swc-expected-error {{parser_err_empty_var_decl}}
var   B 1                              // swc-expected-error {{parser_err_empty_var_decl}}
const C "hello"                        // swc-expected-error {{parser_err_empty_var_decl}}
