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
