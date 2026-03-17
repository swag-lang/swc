#global fileprivate // swc-option sema-only
#global skip
func(T) toto(x: T) {}
#assert(#defined(toto))
