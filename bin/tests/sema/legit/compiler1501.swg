#global fileprivate // swc-option sema-only
#global skip
#test
{
    var toto: [512] u16
    @assert(@countof(toto) == 512)
}
