#global internal

var A: func(s32)
#assert(#nameof(#typeof(A)) == "func(s32)")
var B: func(s32, bool)
#assert(#nameof(#typeof(B)) == "func(s32, bool)")
var C: func(s32, bool)->string
#assert(#nameof(#typeof(C)) == "func(s32, bool)->string")
var D: func(s32, string)->*s32 throw
#assert(#nameof(#typeof(D)) == "func(s32, string)->*s32 throw")
var E: func||(s32)
#assert(#nameof(#typeof(E)) == "func||(s32)")
var F: func||(s32, bool)
#assert(#nameof(#typeof(F)) == "func||(s32, bool)")
var G: func||(s32, bool)->string
#assert(#nameof(#typeof(G)) == "func||(s32, bool)->string")
var H: func||(s32, string)->*s32 throw
#assert(#nameof(#typeof(H)) == "func||(s32, string)->*s32 throw")

var I: func() = null
var J: func(...) = null
var K: func(s32...) = null
#assert(#nameof(#typeof(I)) == "func()")
#assert(#nameof(#typeof(J)) == "func(...)")
#assert(#nameof(#typeof(K)) == "func(s32...)")

var A0: func(a: s32)
#assert(#nameof(#typeof(A0)) == "func(a: s32)")

var BAD: func(s32) = true // swc-expected-error {{sema_err_cannot_cast}}
