#global fileprivate // swc-option sema-only
#global skip
#[Swag.ConstExpr]
func N() => 10
var arr: [N()] s32
