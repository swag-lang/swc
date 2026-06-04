#global fileprivate
using Core, Serialization

#test
{
    let _ = #typeof(Marker)
    @assert(true)
}
