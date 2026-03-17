#global fileprivate // swc-option sema-only
#global skip
var G = 0
#test
{
    var lambda:  func()
    let lambda1: func() = func() { G = 1; }

    let lambda2 = lambda orelse lambda1
    lambda2()
    @assert(G == 1)
}
