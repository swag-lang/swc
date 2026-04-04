#global fileprivate

var value = @countof(1, 2) // swc-expected-error {{parser_err_too_many_arguments}}
