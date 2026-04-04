#assert(false && true) // swc-expected-error {{parser_err_unexpected_and_or}}
#assert(true || false) // swc-expected-error {{parser_err_unexpected_and_or}}
