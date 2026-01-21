#global internal

var A: *s32
#assert(#typeof(A) == *s32)
#assert(#nameof(#typeof(A)) == "*s32")
var B: **s32

var AA: [*]s32
#assert(#typeof(AA) == [*]s32)
#assert(#nameof(#typeof(AA)) == "[*] s32")
var BB: [*][*]s32

var C: const *s32
#assert(#typeof(C) == const *s32)
#assert(#nameof(#typeof(C)) == "const *s32")

var D: const bool // swc-expected-error {{sema_err_bad_type_qualifier}}

var E: const [*]s32
#assert(#typeof(E) == const [*]s32)
#assert(#nameof(#typeof(E)) == "const [*] s32")

var F: const [..]s32
#assert(#typeof(F) == const [..]s32)
#assert(#nameof(#typeof(F)) == "const [..] s32")

var G: *F // swc-expected-error {{sema_err_not_type}}
enum H { A = 0 }
var I: *H
var J: *H.A // swc-expected-error {{sema_err_not_type}}
