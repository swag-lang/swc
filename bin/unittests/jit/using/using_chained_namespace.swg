#global private
using Core, Serialization

#test
{
    let _ = #typeof(Marker)
    discard _
    Swag.assert(true)
}
