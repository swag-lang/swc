// @FAIL
#global skip
#global fileprivate
using Swag

#[ConstExpr]
func main()->s32 { return 555; }

var v = main()

#run
{
    @assert(v == 555)
}
