#global fileprivate // swc-option sema-only
#global skip
#test
{
    let str = "\xc2\x80"
    @assert(str[0] == 0xc2)
    @assert(str[1] == 0x80)
}
