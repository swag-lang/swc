#global fileprivate

// Unknown intrinsics; close spellings trigger a did-you-mean hint, wild ones fall back.
var a = @toto(6)                         // swc-expected-error {{parser_err_invalid_intrinsic}}
var b = @countoff(1)                     // swc-expected-error {{parser_err_invalid_intrinsic}}
var c = @prnt(1)                         // swc-expected-error {{parser_err_invalid_intrinsic}}
var d = @zzz()                           // swc-expected-error {{parser_err_invalid_intrinsic}}
