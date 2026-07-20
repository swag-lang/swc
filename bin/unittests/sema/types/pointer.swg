#global private

var A: #null *s32
#assert(#typeof(A) == #null *s32)
#assert(#nameof(#typeof(A)) == "#null *s32")
var B: #null *#null *s32

var AA: #null [*]s32
#assert(#typeof(AA) == #null [*]s32)
#assert(#nameof(#typeof(AA)) == "#null [*] s32")
var BB: #null [*]#null [*]s32

var C: #null const *s32
#assert(#typeof(C) == #null const *s32)
#assert(#nameof(#typeof(C)) == "#null const *s32")

var E: #null const [*]s32
#assert(#typeof(E) == #null const [*]s32)
#assert(#nameof(#typeof(E)) == "#null const [*] s32")

var F: #null const [..]s32
#assert(#typeof(F) == #null const [..]s32)
#assert(#nameof(#typeof(F)) == "#null const [..] s32")

enum H { A = 0 }
var I: #null *H
