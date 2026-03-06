#global fileprivate
using Swag

#[ConstExpr]
func main()->s32 { return 555; }

const v = main()

#run
{
    @assert(v == 555)
}
