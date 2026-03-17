// 

#global fileprivate
using A.B

namespace A.B
{
    func main()->bool { return true }
}

#test
{
    @assert(main())
}
