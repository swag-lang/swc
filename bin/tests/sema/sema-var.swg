#global internal

var A: s32 = true                 // swc-expected-error {{sema_err_cannot_cast}}
var B: s32
var C: f32 = 1
#assert(#typeof(C) == f32)