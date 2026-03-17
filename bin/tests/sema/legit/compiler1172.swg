#global fileprivate // swc-option sema-only
#global skip
const A = true
const B = A ? true : false
#assert(B == true)
