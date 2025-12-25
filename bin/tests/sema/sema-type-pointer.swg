#global internal

var A: *s32
#assert(#typeof(A) == *s32)
#assert(#nameof(#typeof(A)) == "*s32")
var B: **s32

var AA: [*]s32
#assert(#typeof(AA) == [*]s32)
#assert(#nameof(#typeof(AA)) == "[*]s32")
var BB: [*][*]s32