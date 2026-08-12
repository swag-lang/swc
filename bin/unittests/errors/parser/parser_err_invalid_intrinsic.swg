#global private

// Unknown intrinsics; close spellings trigger a did-you-mean hint, wild ones fall back.
var a = @toto(6)                         // swc-expected-error {{parser_err_invalid_intrinsic}}
var b = @countoff(1)                     // swc-expected-error {{parser_err_invalid_intrinsic}}
var c = @prnt(1)                         // swc-expected-error {{parser_err_invalid_intrinsic}}
var d = @zzz()                           // swc-expected-error {{parser_err_invalid_intrinsic}}
var e = @cvastart(1)                     // swc-expected-error {{parser_err_invalid_intrinsic}}
var f = @cvaend(1)                       // swc-expected-error {{parser_err_invalid_intrinsic}}
var g = @cvaarg(1, u32)                  // swc-expected-error {{parser_err_invalid_intrinsic}}
var h = @alloc(16)                       // swc-expected-error {{parser_err_invalid_intrinsic}}
var i = @realloc(null, 16)               // swc-expected-error {{parser_err_invalid_intrinsic}}
var j = @free(null)                      // swc-expected-error {{parser_err_invalid_intrinsic}}
