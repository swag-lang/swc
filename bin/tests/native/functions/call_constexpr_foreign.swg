#global fileprivate
#global #if #os == Swag.TargetOs.Windows

#[Swag.ConstExpr]
#[Swag.Foreign(link: "ucrt", function: "abs", module: "ucrtbase")]
func CAbs(value: s32)->s32;

func useForeignConstExpr()->s32
{
    const A = CAbs(-7)
    return A + CAbs(-5)
}

func useForeignRuntime(value: s32)->s32
{
    return CAbs(value) + 1
}

#test
{
    const A = CAbs(-7)
    #assert(A == 7)
    @assert(CAbs(-9) == 9)
    @assert(useForeignConstExpr() == 12)
    var runtimeValue = -11
    @assert(useForeignRuntime(runtimeValue) == 12)
}
