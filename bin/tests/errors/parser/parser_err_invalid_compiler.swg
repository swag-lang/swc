#global fileprivate

var a = #toto // swc-expected-error {{parser_err_invalid_compiler}}
var b = #sizeoff(s32) // swc-expected-error {{parser_err_invalid_compiler}}
