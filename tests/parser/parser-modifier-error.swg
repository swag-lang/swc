var a = #toto // swc-expected-error {{parser_err_invalid_compiler}}
var a = @toto(6) // swc-expected-error {{parser_err_invalid_intrinsic}}
var a = me.@t // swc-expected-error {{parser_err_invalid_intrinsic}}