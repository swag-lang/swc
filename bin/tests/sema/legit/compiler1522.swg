#global fileprivate // swc-option sema-only
#global skip
struct X
{
    x:     s32
    y:     bool
}

#test
{
    var p: X{y: true, x: 666}
    @assert(p.x == 666)
    @assert(p.y == true)
}
