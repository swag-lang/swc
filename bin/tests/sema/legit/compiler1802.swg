#global fileprivate // swc-option sema-only
#global skip
#[Swag.ConstExpr]
func plus(x: u32) => x == 10
const C = plus(10)
#assert(C == true)
