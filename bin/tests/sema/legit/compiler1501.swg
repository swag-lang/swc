#global fileprivate
#global skip
#test
{
    var toto: [512] u16
    @assert(@countof(toto) == 512)
}
