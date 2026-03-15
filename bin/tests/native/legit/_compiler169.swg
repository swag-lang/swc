// swc-option suite-test

#global fileprivate
using Swag

#[ConstExpr]
func main()->s32
{
    //@print("toto\n");
    return 666
}

#test
{
    var r = main()
    @assert(r == 666)
}
