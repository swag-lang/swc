#global fileprivate

// Unknown compiler instructions; close spellings trigger a did-you-mean hint, wild ones fall back.
var a = #toto                            // swc-expected-error {{parser_err_invalid_compiler}}
var b = #sizeoff(s32)                    // swc-expected-error {{parser_err_invalid_compiler}}
var c = #asser(true)                     // swc-expected-error {{parser_err_invalid_compiler}}
var d = #xyz                             // swc-expected-error {{parser_err_invalid_compiler}}
