// 

#global fileprivate
#global skip
//#[Swag.PrintBc]
#test
{
    let s   = 1
    var res = false
    switch s
    {
    case 1:
        fallthrough
    case 2:
        fallthrough
    case 3:
        res = true
    }
    @assert(res)
}
