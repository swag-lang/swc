#global fileprivate // swc-option sema-only
#global skip
const X: u32 = true ? 0xFF : 0
#assert(X == 0xFF)
const X1: u32 = false ? 0xFF : 6
#assert(X1 == 6)
