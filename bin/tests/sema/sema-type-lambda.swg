#global internal

var A: func(s32)
#assert(#nameof(#typeof(A)) == "func(s32)")