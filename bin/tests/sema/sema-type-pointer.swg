#global internal

var A: *s32
#assert(#typeof(A) == *s32)
#assert(#nameof(#typeof(A)) == "*s32")
var B: **s32

var AA: [*]s32
#assert(#typeof(AA) == [*]s32)
#assert(#nameof(#typeof(AA)) == "[*]s32")
var BB: [*][*]s32

var C: const *s32
#assert(#typeof(C) == const *s32)
#assert(#nameof(#typeof(C)) == "const *s32")

var D: const bool // swc-expected-error {{sema_err_bad_type_qualifier}}