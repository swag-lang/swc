#global fileprivate
#global skip
#[Swag.ConstExpr]
func N() => 10

#assert(#typeof(N()) == #typeof(10))

var arr: [N()] s32
