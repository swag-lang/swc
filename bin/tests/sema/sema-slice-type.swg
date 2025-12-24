#global internal

var A: [..]s32
#assert(#typeof(A) == [..]s32)
#assert(#nameof(#typeof(A)) == "[..]s32")
