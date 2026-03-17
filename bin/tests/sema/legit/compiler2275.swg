#global fileprivate // swc-option sema-only
#global skip
#test
{
    var ptr: [*] [*] void
    ptr += 1
    @assert(cast(u64) ptr == #sizeof(*void))
}
