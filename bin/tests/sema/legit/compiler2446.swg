#global fileprivate
#global skip
#[Swag.ConstExpr]
func N() => 10

#assert(#typeof(N()) == s8)

var arr: [N()] s32
