#global internal

var A: func(s32)
#assert(#nameof(#typeof(A)) == "func(s32)")
var B: func(s32, bool)
#assert(#nameof(#typeof(B)) == "func(s32, bool)")
var C: func(s32, bool)->string
#assert(#nameof(#typeof(C)) == "func(s32, bool)->string")
var D: func(s32, string)->*s32 throw
#assert(#nameof(#typeof(D)) == "func(s32, string)->*s32 throw")
