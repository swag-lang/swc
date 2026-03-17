#global fileprivate // swc-option sema-only
#global skip
attr myAttribute()

#[myAttribute]
func function() {}

#[myAttribute]
struct A {}
