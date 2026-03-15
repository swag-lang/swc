#global #if #os == Swag.TargetOs.Windows

#[Swag.Foreign(link: "ucrt", function: "abs", module: "ucrtbase")]
func CAbs(value: s32)->s32;

#test
{
    const A = #run CAbs(-7)
    const B = #run CAbs(42)
    #assert(A == 7)
    #assert(B == 42)
}
