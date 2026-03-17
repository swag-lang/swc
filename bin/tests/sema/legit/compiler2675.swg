#global fileprivate // swc-option sema-only
#global skip
#test
{
    let aa: const [..] s32 = [10, 20]
    let vv  = {aa}
    @assert(vv.item0[0] == 10)
    @assert(vv.item0[1] == 20)
}
