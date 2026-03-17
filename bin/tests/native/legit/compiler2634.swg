// 

#global fileprivate
#global skip
using Swag

#[Compiler]
var G = 0

#[Compiler]
func toto()
{
    for 10 do
        G += 1
}

#test
{
    toto()
    @assert(G == 10)
}
