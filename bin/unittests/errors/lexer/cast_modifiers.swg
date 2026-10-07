let optional = cast #try(*s32, value)       // swc-expected-error {{parser_err_invalid_compiler}}
let required = cast #assume(*s32, value)    // swc-expected-error {{parser_err_invalid_compiler}}
