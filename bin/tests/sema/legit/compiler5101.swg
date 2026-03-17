#global fileprivate // swc-option sema-only
#global skip
//#global testerror "Err0725"

alias B = f32
const A = 1'B
#assert(#typeof(A) == f32)
