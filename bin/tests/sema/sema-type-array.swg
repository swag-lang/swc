#global internal

var A: [?] s32
#assert(#nameof(#typeof(A)) == "[?] s32")
#assert(#nameof(#typeof(A)) != "[?] bool")

var B: [A] s32 // swc-expected-error {{sema_err_expr_not_const}}
enum C { A}
var D: [C] s32 // swc-expected-error {{sema_err_not_value_expr}}
var E: [1, C] s32 // swc-expected-error {{sema_err_not_value_expr}}

var F: [2, 3, 4] s32
#assert(#nameof(#typeof(F)) == "[2, 3, 4] s32")

var G: [2.0] s32    // swc-expected-error {{sema_err_array_dim_not_int}}
var H: [0] s32      // swc-expected-error {{sema_err_array_dim_zero}}
var I: [-1] s32     // swc-expected-error {{sema_err_array_dim_negative}}
var J: [0xFFFFFFFF_FFFFFFFF_FFF] bool // swc-expected-error {{sema_err_literal_too_big}}
