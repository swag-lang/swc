#global fileprivate

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

var E: const [*]s32
#assert(#typeof(E) == const [*]s32)
#assert(#nameof(#typeof(E)) == "const [*] s32")

var F: const [..]s32
#assert(#typeof(F) == const [..]s32)
#assert(#nameof(#typeof(F)) == "const [..] s32")

enum H { A = 0 }
var I: *H
