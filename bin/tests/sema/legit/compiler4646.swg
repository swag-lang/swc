#global fileprivate // swc-option sema-only
#global skip
#test
{
    const x = 255
    @assert(@max(x, 0) == 255)
}
