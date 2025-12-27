#global internal

var A: [..] s32
#assert(#typeof(A) == [..] s32)
#assert(#nameof(#typeof(A)) == "[..] s32")

var B: [..] void // swc-expected-error {{sema_err_bad_slice_element_type}}
