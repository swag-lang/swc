// 

#global fileprivate
using Swag

//#[PrintBc]
func toto()->s32
{
    var a = 0
    while a < 10
    {
        a += 1
        for
        {
            break
        }
    }

    @assert(a == 10)
    return a
}

#test
{
    @assert(toto() == 10)
}
