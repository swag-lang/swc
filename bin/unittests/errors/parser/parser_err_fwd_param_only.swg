#global private

struct Vec { x: s32 }

// '#fwd' is a parameter-type prefix: it cannot type a variable.
var g_bad: #fwd Vec // swc-expected-error {{parser_err_fwd_param_only}}
