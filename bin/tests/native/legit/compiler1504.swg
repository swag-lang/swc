// 

#global fileprivate
#global skip
var X: u32 = undefined

#[Swag.Compiler]
func set()
{
    X = 6
}

//#[Swag.PrintBc]
#test
{
    #run set()
    @assert(X == 6)
}
