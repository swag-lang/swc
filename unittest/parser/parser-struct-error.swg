struct(var T : s32) A { } // swc-expected-error {{parser_err_gen_param_type}}
struct(T = 0) A { } // swc-expected-error {{parser_err_invalid_type}}

