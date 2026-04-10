#global fileprivate

var a = @toto(6) // swc-expected-error {{parser_err_invalid_intrinsic}}
var b = @countoff(1) // swc-expected-error {{parser_err_invalid_intrinsic}}
