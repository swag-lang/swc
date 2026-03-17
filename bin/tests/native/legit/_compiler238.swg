// 

#global fileprivate
using Swag

//#[PrintBc]
func main()->s32
{
    var a = 1
    var b = 666
    a = b; @assert(a == 666)
    b = 10; a += b; @assert(a == 676)
    return a
}

#test
{
    @assert(main() == 676)
}
