#global fileprivate
#global skip
#[Swag.ConstExpr]
func N() => 10

#assert(#typeof(N()) == #typeof(10))

const ArrCount = cast(s32) N()
var arr: [ArrCount] s32
